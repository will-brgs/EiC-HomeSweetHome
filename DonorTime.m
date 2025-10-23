%  DONATION ANALYSIS SCRIPT
close all; clc;
%% --- Plot settings ---
if exist('orderedcolors', 'file')
    gemColors = orderedcolors("gem");
else
    gemColors = lines(10); % fallback color palette
end
linewidth = 1.5;
color1 = gemColors(5,:);
color2 = gemColors(7,:);
%% --- Load and clean data ---
dataRaw = readtable('TransactionsToPresentData.csv', 'VariableNamingRule', 'preserve');
data = dataRaw(6:end, :);  % remove first 5 rows
% Keep relevant columns
donationData = data(:, {'Account Number', 'Date', 'Amount'});
% Fix column name for convenience
donationData.Properties.VariableNames{'Account Number'} = 'AccountNumber';
% Convert Date to datetime
donationData.Date = datetime(donationData.Date, 'InputFormat', 'MM/dd/yyyy');
% Clean and convert Amount
donationData.Amount = strrep(donationData.Amount, '$', '');
donationData.Amount = str2double(donationData.Amount);
donationData.Amount(isnan(donationData.Amount)) = 0;
% Convert to THOUSANDS of dollars
donationData.Amount = donationData.Amount / 1000;
%% ========================
%% --- DAILY TOTALS & COUNTS ---
%% ========================
allDates = (min(donationData.Date):max(donationData.Date))';
[uniqueDates, ~, idx] = unique(donationData.Date);
sumAmounts = accumarray(idx, donationData.Amount);
countDonations = accumarray(idx, 1);
dailyTable = table(allDates, zeros(length(allDates),1), zeros(length(allDates),1), ...
    'VariableNames', {'Date','TotalAmount','DonationCount'});
[~, ia, ib] = intersect(dailyTable.Date, uniqueDates);
dailyTable.TotalAmount(ia) = sumAmounts(ib);
dailyTable.DonationCount(ia) = countDonations(ib);
%% =========================
%% --- DAILY COMBINED PLOT ---
%% =========================
figure;
tiledlayout(2,1);
nexttile;
plot(dailyTable.Date, dailyTable.TotalAmount, 'Color', color1, 'LineWidth', linewidth);
xlabel('Date'); ylabel('Amount Donated (Thousands of $)');
title('Daily Total Donations'); grid on;
nexttile;
plot(dailyTable.Date, dailyTable.DonationCount, 'Color', color2, 'LineWidth', linewidth);
xlabel('Date'); ylabel('Number of Donations');
title('Daily Donation Count'); grid on;
%% =========================
%% --- WEEKDAY BAR CHARTS (AMOUNT + COUNT) ---
%% =========================
dailyTable.Weekday = categorical(day(dailyTable.Date, 'name'), ...
    {'Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'}, ...
    'Ordinal', true);
avgAmountByDay = groupsummary(dailyTable, 'Weekday', 'mean', 'TotalAmount');
avgCountByDay  = groupsummary(dailyTable, 'Weekday', 'mean', 'DonationCount');
figure;
tiledlayout(2,1);
nexttile;
bar(avgAmountByDay.Weekday, avgAmountByDay.mean_TotalAmount, ...
    'FaceColor', color1, 'EdgeColor', 'none');
xlabel('Day of Week');
ylabel('Average Amount Donated (Thousands of $)');
title('Average Donations by Weekday');
grid on;
nexttile;
bar(avgCountByDay.Weekday, avgCountByDay.mean_DonationCount, ...
    'FaceColor', color2, 'EdgeColor', 'none');
xlabel('Day of Week');
ylabel('Average Number of Donations');
title('Average Donation Count by Weekday');
grid on;
%% ==========================================
%% --- MONTHLY AVERAGE PLOTS (BY MONTH OF YEAR) ---
%% ==========================================
% Get month name, ordered chronologically
monthNames = {'January','February','March','April','May','June','July',...
              'August','September','October','November','December'};
dailyTable.MonthOfYear = categorical(month(dailyTable.Date, 'name'), ...
    monthNames, 'Ordinal', true);

% Calculate average daily amount and count, grouped by month of year
avgAmountByMonthOfYear = groupsummary(dailyTable, 'MonthOfYear', 'mean', 'TotalAmount');
avgCountByMonthOfYear  = groupsummary(dailyTable, 'MonthOfYear', 'mean', 'DonationCount');

figure;
tiledlayout(2,1);

% --- Plot 1: Average Amount by Month of Year ---
nexttile;
bar(avgAmountByMonthOfYear.MonthOfYear, avgAmountByMonthOfYear.mean_TotalAmount, ...
    'FaceColor', color1, 'EdgeColor', 'none');
xlabel('Month');
ylabel('Average Daily Amount (Thousands of $)');
title('Average Daily Donations by Month of Year');
grid on;
set(gca, 'XTickLabel', monthNames); % Ensure all month names are shown

% --- Plot 2: Average Count by Month of Year ---
nexttile;
bar(avgCountByMonthOfYear.MonthOfYear, avgCountByMonthOfYear.mean_DonationCount, ...
    'FaceColor', color2, 'EdgeColor', 'none');
xlabel('Month');
ylabel('Average Daily Number of Donations');
title('Average Daily Donation Count by Month of Year');
grid on;
set(gca, 'XTickLabel', monthNames); % Ensure all month names are shown
%% =========================
%% --- INDIVIDUAL FFT ANALYSIS ---
%% =========================
fprintf('\n=== FFT Analysis: Donation Frequency by Donor ===\n');
uniqueAccounts = unique(donationData.AccountNumber);
freqResults = table();
for i = 1:length(uniqueAccounts)
    acct = uniqueAccounts(i);
    acctData = donationData(donationData.AccountNumber == acct, :);
    acctData = sortrows(acctData, 'Date');
    
    if height(acctData) < 3
        continue; % skip accounts with too few donations
    end
    
    % Create daily signal: 1 if donation occurred, 0 otherwise
    allDays = (min(acctData.Date):max(acctData.Date))';
    
    L = length(allDays); % Get length L
    
    % Need at least 2 days (L=2) for a frequency component P1(2)
    if L < 2 
        continue;
    end
    
    donationsDaily = ismember(allDays, acctData.Date);
    y = donationsDaily - mean(donationsDaily);
    
    Fs = 1; % 1 sample per day
    Y = fft(y);
    P2 = abs(Y / L);
    P1 = P2(1:floor(L/2)+1);
    P1(2:end-1) = 2 * P1(2:end-1);
    freq = Fs * (0:floor(L/2)) / L;
    period_days = 1 ./ freq;
    period_days(isinf(period_days)) = NaN;
    
    % Store dominant frequency
    [~, maxIdx] = max(P1(2:end)); % skip DC
    
    dominantPeriod = period_days(maxIdx + 1); 
    
    freqResults = [freqResults; table(acct, dominantPeriod)];
end
figure;
% *** CHANGE: Using 50 bins for better granularity in the new range
histogram(freqResults.dominantPeriod, 50, 'FaceColor', color1);
xlabel('Dominant Donation Period (days)');
ylabel('Number of Donors');
title('Histogram of Individual Donation Frequencies');
% *** CHANGE: Set x-axis limit from 1 day to 2 years (730 days)
xlim([1, 730]);
grid on;
%% =========================
%% --- SMOOTHING & CORRELATION ---
%% =========================
dailyTable.SmoothedAmount = movmean(dailyTable.TotalAmount, 7);
dailyTable.SmoothedCount  = movmean(dailyTable.DonationCount, 7);
figure;
tiledlayout(2,1);
nexttile;
% *** CHANGE: Removed plot of raw data
plot(dailyTable.Date, dailyTable.SmoothedAmount, 'Color', color1, 'LineWidth', linewidth*1.2);
hold on;
xlabel('Date'); ylabel('Amount Donated (Thousands of $)');
title('Daily Total Donations (7-Day Smoothed)');
% *** CHANGE: Removed legend
grid on;
nexttile;
% *** CHANGE: Removed plot of raw data
plot(dailyTable.Date, dailyTable.SmoothedCount, 'Color', color2, 'LineWidth', linewidth*1.2);
hold on;
xlabel('Date'); ylabel('Number of Donations');
title('Daily Donation Count (7-Day Smoothed)');
% *** CHANGE: Removed legend
grid on;
% Correlation
corr_val = corr(dailyTable.TotalAmount, dailyTable.DonationCount, 'Rows', 'complete');
fprintf('\nCorrelation between daily amount and donation count: %.3f\F\n', corr_val);