%% Donation Analysis Script - Continuous Time Axes
close all; clc;

%% Plot settings

gemColors = orderedcolors("gem");

linewidth = 1.5;
color1 = gemColors(5,:);
color2 = gemColors(7,:);

%% Load and clean data
dataRaw = readtable('TransactionsToPresentData.csv');
data = dataRaw(6:end, :);  % remove first 5 rows
donationData = data(:, {'Date', 'Amount'});

% Convert Date to datetime
donationData.Date = datetime(donationData.Date, 'InputFormat', 'MM/dd/yyyy');

% Clean Amount column
donationData.Amount = strrep(donationData.Amount, '$', '');
donationData.Amount = str2double(donationData.Amount);
donationData.Amount(isnan(donationData.Amount)) = 0;
donationData.Amount = donationData.Amount / 100;  % convert to hundreds of dollars

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

% Plot daily data
figure
plot(dailyTable.Date, dailyTable.TotalAmount, 'Color', color1, 'LineWidth', linewidth);
xlabel('Date'); ylabel('Amount Donated (Hundreds of $)'); title('Daily Total Donations'); grid on;

figure
plot(dailyTable.Date, dailyTable.DonationCount, 'Color', color2, 'LineWidth', linewidth);
xlabel('Date'); ylabel('Number of Donations'); title('Daily Donation Count'); grid on;

%% =========================
%% --- WEEKLY TOTALS & COUNTS ---
%% =========================
donationData.Week = dateshift(donationData.Date, 'start', 'week');
allWeeks = (dateshift(min(donationData.Date),'start','week') : 7 : dateshift(max(donationData.Date),'start','week'))';

[uniqueWeeks, ~, idxW] = unique(donationData.Week);
weeklyAmountVals = accumarray(idxW, donationData.Amount);
weeklyCountVals = accumarray(idxW, 1);

weeklyTable = table(allWeeks, zeros(length(allWeeks),1), zeros(length(allWeeks),1), ...
    'VariableNames', {'Week','TotalAmount','DonationCount'});

[~, ia, ib] = intersect(weeklyTable.Week, uniqueWeeks);
weeklyTable.TotalAmount(ia) = weeklyAmountVals(ib);
weeklyTable.DonationCount(ia) = weeklyCountVals(ib);

% Plot weekly data
figure
plot(weeklyTable.Week, weeklyTable.TotalAmount, 'Color', color1, 'LineWidth', linewidth);
xlabel('Week'); ylabel('Amount Donated (Hundreds of $)'); title('Weekly Total Donations'); grid on;

figure
plot(weeklyTable.Week, weeklyTable.DonationCount, 'Color', color2, 'LineWidth', linewidth);
xlabel('Week'); ylabel('Number of Donations'); title('Weekly Donation Count'); grid on;

%% =========================
%% --- MONTHLY TOTALS & COUNTS ---
%% =========================
donationData.Month = dateshift(donationData.Date, 'start', 'month');
allMonths = (dateshift(min(donationData.Date),'start','month') : calmonths(1) : dateshift(max(donationData.Date),'start','month'))';

[uniqueMonths, ~, idxM] = unique(donationData.Month);
monthlyAmountVals = accumarray(idxM, donationData.Amount);
monthlyCountVals = accumarray(idxM, 1);

monthlyTable = table(allMonths, zeros(length(allMonths),1), zeros(length(allMonths),1), ...
    'VariableNames', {'Month','TotalAmount','DonationCount'});

[~, ia, ib] = intersect(monthlyTable.Month, uniqueMonths);
monthlyTable.TotalAmount(ia) = monthlyAmountVals(ib);
monthlyTable.DonationCount(ia) = monthlyCountVals(ib);

% Plot monthly data
figure
plot(monthlyTable.Month, monthlyTable.TotalAmount, 'Color', color1, 'LineWidth', linewidth);
xlabel('Month'); ylabel('Amount Donated (Hundreds of $)'); title('Monthly Total Donations'); grid on;

figure
plot(monthlyTable.Month, monthlyTable.DonationCount, 'Color', color2, 'LineWidth', linewidth);
xlabel('Month'); ylabel('Number of Donations'); title('Monthly Donation Count'); grid on;
