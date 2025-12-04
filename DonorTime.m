%% =====================================================
%  DONATION ANALYSIS SCRIPT (WITH SUBGROUP LOOPING + COMPARISONS)
% ======================================================
close all; clc;

%% --- Plot settings ---
gemColors = orderedcolors("gem");
linewidth = 1.5;
color1 = gemColors(5,:);
color2 = gemColors(7,:);

%% --- Load and clean data ---
dataRaw = readtable('TransactionsToPresentData.csv', 'VariableNamingRule', 'preserve');
data = dataRaw(6:end, :);  % remove first 5 rows

% Convert columns to string type for logic
data.Type = string(data.Type);
data.Groups = string(data.Groups);

%% --- Define Subgroups ---
isOrganization = contains(data.Groups, "Organizations", 'IgnoreCase', true) | ...
                 strcmpi(data.Type, "Pledge") | ...
                 (strcmpi(data.Type, "Recurring Donation Payment") & contains(data.Groups, "Organizations", 'IgnoreCase', true));

isRecurring = strcmpi(data.Type, "Recurring Donation Payment");
isIndividual = ~isOrganization;  % all others

% Store subgroup masks in a structure
subgroups = struct();
subgroups.All = true(height(data),1);
subgroups.Organizations = isOrganization;
subgroups.MonthlyDonors = isRecurring;
subgroups.Individuals = isIndividual;

groupNames = fieldnames(subgroups);

%% --- Initialize result storage ---
results = struct();

%% --- Loop through each subgroup ---
for g = 1:numel(groupNames)
    groupName = groupNames{g};
    fprintf('\n===== Processing group: %s =====\n', groupName);

    % --- Filter data for this group ---
    groupMask = subgroups.(groupName);
    groupData = data(groupMask, :);
    if isempty(groupData), continue; end

    %% --- CLEAN & PREP DATA ---
    donationData = groupData(:, {'Account Number', 'Date', 'Amount'});
    donationData.Properties.VariableNames{'Account Number'} = 'AccountNumber';
    donationData.Date = datetime(donationData.Date, 'InputFormat', 'MM/dd/yyyy');
    donationData.Amount = strrep(donationData.Amount, '$', '');
    donationData.Amount = str2double(donationData.Amount);
    donationData.Amount(isnan(donationData.Amount)) = 0;
    donationData.Amount = donationData.Amount / 1000; % in thousands

% Combine same-account donations on same day (count once)
[~, ia] = unique(donationData(:, {'AccountNumber', 'Date'}), 'rows');
donationData = donationData(ia, :);


    %% --- DAILY TOTALS & COUNTS ---
    allDates = (min(donationData.Date):max(donationData.Date))';
    [uniqueDates, ~, idx] = unique(donationData.Date);
    sumAmounts = accumarray(idx, donationData.Amount);
    countDonations = accumarray(idx, 1);

    dailyTable = table(allDates, zeros(length(allDates),1), zeros(length(allDates),1), ...
        'VariableNames', {'Date','TotalAmount','DonationCount'});
    [~, ia, ib] = intersect(dailyTable.Date, uniqueDates);
    dailyTable.TotalAmount(ia) = sumAmounts(ib);
    dailyTable.DonationCount(ia) = countDonations(ib);

    %% --- DAILY DONATION SUMMARY ---
    figure;
    tiledlayout(2,1);
    nexttile;

    if strcmp(groupName, 'MonthlyDonors')
        % Lollipop plot for monthly donors
        stem(dailyTable.Date, dailyTable.TotalAmount, 'Color', color1, ...
            'LineWidth', linewidth, 'Marker', 'o', 'MarkerFaceColor', color1);
    else
        plot(dailyTable.Date, dailyTable.TotalAmount, 'Color', color1, 'LineWidth', linewidth);
    end

    xlabel('Date'); ylabel('Amount Donated (Thousands of $)');
    title('Daily Total Donations'); grid on;

    nexttile;
    plot(dailyTable.Date, dailyTable.DonationCount, 'Color', color2, 'LineWidth', linewidth);
    xlabel('Date'); ylabel('Number of Donations');
    title('Daily Donation Count'); grid on;

    sgtitle(sprintf('Daily Donation Summary — %s', groupName));

    %% --- WEEKDAY & MONTHLY BAR CHARTS ---
    dailyTable.Weekday = categorical(day(dailyTable.Date, 'name'), ...
        {'Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'}, 'Ordinal', true);
    avgAmountByDay = groupsummary(dailyTable, 'Weekday', 'mean', 'TotalAmount');
    avgCountByDay  = groupsummary(dailyTable, 'Weekday', 'mean', 'DonationCount');

    figure;
    tiledlayout(2,1);
    nexttile;
    bar(avgAmountByDay.Weekday, avgAmountByDay.mean_TotalAmount, ...
        'FaceColor', color1, 'EdgeColor', 'k');
    xlabel('Day of Week'); ylabel('Average Amount Donated (Thousands of $)');
    title('Average Donations by Weekday'); grid on;

    nexttile;
    bar(avgCountByDay.Weekday, avgCountByDay.mean_DonationCount, ...
        'FaceColor', color2, 'EdgeColor', 'k');
    xlabel('Day of Week'); ylabel('Average Number of Donations');
    title('Average Donation Count by Weekday'); grid on;
    sgtitle(sprintf('Weekday Donation Behavior — %s', groupName));

    % --- Monthly Trends ---
    monthNames = {'January','February','March','April','May','June','July',...
                  'August','September','October','November','December'};
    dailyTable.MonthOfYear = categorical(month(dailyTable.Date, 'name'), monthNames, 'Ordinal', true);
    avgAmountByMonth = groupsummary(dailyTable, 'MonthOfYear', 'mean', 'TotalAmount');
    avgCountByMonth  = groupsummary(dailyTable, 'MonthOfYear', 'mean', 'DonationCount');

    figure;
    tiledlayout(2,1);
    nexttile;
    bar(avgAmountByMonth.MonthOfYear, avgAmountByMonth.mean_TotalAmount, ...
        'FaceColor', color1, 'EdgeColor', 'k');
    xlabel('Month'); ylabel('Average Daily Amount (Thousands of $)');
    title('Average Daily Donations by Month'); grid on;

    nexttile;
    bar(avgCountByMonth.MonthOfYear, avgCountByMonth.mean_DonationCount, ...
        'FaceColor', color2, 'EdgeColor', 'k');
    xlabel('Month'); ylabel('Average Daily Number of Donations');
    title('Average Daily Donation Count by Month'); grid on;
    sgtitle(sprintf('Monthly Donation Trends — %s', groupName));

    %% --- FFT: DONATION FREQUENCY PER ACCOUNT ---
    fprintf('\n=== FFT Analysis: Donation Frequency for %s ===\n', groupName);
    uniqueAccounts = unique(donationData.AccountNumber);
    freqResults = table();
    bins = [400,300,30,400];

    for i = 1:length(uniqueAccounts)
        acct = uniqueAccounts(i);
        acctData = donationData(donationData.AccountNumber == acct, :);
        acctData = sortrows(acctData, 'Date');

        if height(acctData) < 3, continue; end

        allDays = (min(acctData.Date):max(acctData.Date))';
        donationsDaily = ismember(allDays, acctData.Date);
        y = donationsDaily - mean(donationsDaily);
        L = length(allDays);
        if L < 2, continue; end
        Fs = 1;
        Y = fft(y);
        P2 = abs(Y/L);
        P1 = P2(1:floor(L/2)+1);
        P1(2:end-1) = 2*P1(2:end-1);
        freq = Fs*(0:floor(L/2))/L;
        period_days = 1./freq;
        period_days(isinf(period_days)) = NaN;

        [~, maxIdx] = max(P1(2:end));
        dominantPeriod = period_days(maxIdx + 1);
        freqResults = [freqResults; table(acct, dominantPeriod)];
    end

    figure;
    histogram(freqResults.dominantPeriod,bins(g), 'FaceColor', color1, 'EdgeColor', 'k');
    xlabel('Dominant Donation Period (days)');
    ylabel('Frequency Intensity');
    title(sprintf('Donation Frequency — %s', groupName));
    grid on;
    if g==1 % all
    xlim([1, 400]);
    elseif g==2 % orgs
    xlim([1, 400]);
    elseif g==3 % monthly
    xlim([1, 100]);
    elseif g==4 %invidivuals
    xlim([1, 400]);
    end

    %% --- Save Results ---
    results.(groupName) = struct('daily', dailyTable, ...
                                 'freq', freqResults, ...
                                 'avgWeekday', avgAmountByDay, ...
                                 'avgMonth', avgAmountByMonth);
end

fprintf('\n=== All subgroup analyses complete! ===\n');

%% =========================================================
%  COMPARISON SECTION: CROSS-GROUP VISUALIZATIONS
% =========================================================
compareGroups = fieldnames(results);

% --- Compare average monthly donations (subplot version, varying axis) ---
figure;
tiledlayout(2,2);
for g = 1:numel(compareGroups)
    nexttile;
    d = results.(compareGroups{g}).avgMonth;
    bar(d.MonthOfYear, d.mean_TotalAmount, 'FaceColor', gemColors(mod(g, size(gemColors,1))+1,:), 'EdgeColor', 'k');
    if g==3 
        ylim([0,0.08]);
    end
    title(compareGroups{g}); ylabel('Avg Daily Donations (Thousands $)');
    xtickangle(45); grid on;
end
sgtitle('Average Monthly Donations — All Groups - Variable Axis');


% --- Compare average monthly donations (subplot version) ---
figure;
tiledlayout(2,2);
for g = 1:numel(compareGroups)
    nexttile;
    d = results.(compareGroups{g}).avgMonth;
    bar(d.MonthOfYear, d.mean_TotalAmount, 'FaceColor', gemColors(mod(g, size(gemColors,1))+1,:), 'EdgeColor', 'k');
        ylim([0,2.5]);
    title(compareGroups{g}); ylabel('Avg Daily Donations (Thousands $)');
    xtickangle(45); grid on;
end
sgtitle('Average Monthly Donations — All Groups - Static Axis');
%% Save figures
% figHandles = findall(0, 'Type', 'figure');
% filepath = "C:\Users\willb\OneDrive - Washington University in St. Louis\. Engineers in The Community\Figures";
% for n = 1:length(figHandles)
%     fh = figHandles(n);
%     figure(fh);
%     filename = fullfile(filepath, sprintf('figure_%d.jpg', n));
%     exportgraphics(fh, filename, 'Resolution', 300);
%     disp('fig saved')
% end