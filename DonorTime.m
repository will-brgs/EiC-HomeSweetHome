close all
clc

dataRaw = readtable('TransactionsToPresentData.csv');

data = dataRaw(6:end, :);
donationData = data(:, {'Date', 'Amount'});

donationData.Date = datetime(donationData.Date, 'InputFormat', 'MM/dd/yyyy'); % Convert date strings to datetime format

donationData.Amount = strrep(donationData.Amount, '$', ''); % Remove dollar signs from Amount
donationData.Amount = str2double(donationData.Amount); % Convert Amount to numeric values
donationData.Amount(isnan(donationData.Amount)) = 0; % Replace NaN values with 0
% Group by date and sum amounts to prevent repeating data points
donationData = varfun(@sum, donationData, 'InputVariables', 'Amount', 'GroupingVariables', 'Date');
fh1 = figure(1); % Create a new figure

plot(donationData.Date, donationData.Amount); % Plot the data with lines and markers
xlabel('Date'); 
ylabel('Amount Donated'); 
title('Donations Over Time');
grid on; 
