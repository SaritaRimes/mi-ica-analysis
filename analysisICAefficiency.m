%% Efficiency Analysis %%
% Methods: OF, COF, Gaussian MLE e ICA MLE %
% Data: it was generated using the new simulator (github.com/ingoncalves/calorimetry-pulse-simulator) %

clear all
close all
clc

addpath('internalMethods', 'externalMethods', 'FastICA_25');

mean_error_gauss = zeros(11, 1);
mean_error_of = zeros(11, 1);
mean_error_cof = zeros(11, 1);
mean_error_ica = zeros(11, 1);
std_error_gauss = zeros(11, 1);
std_error_of = zeros(11, 1);
std_error_cof = zeros(11, 1);
std_error_ica = zeros(11, 1);

mPu = 50;
snr = 2;
bins = 200;
number_events_total = 2000000;
number_dimensions = 7;

occupancies = [10 30 50 80];

for oc = occupancies

    noise = load(['../../../RuidoSimuladoNovoSimulador/TileCal/ruido_media' int2str(mPu) '/ruido_ocup' int2str(oc) '_' ...
                  int2str(number_events_total) 'sinais.txt']); % load noise data
    noise = noise(1:100000, :);
    pedestal = 50;
%     noise = noise - pedestal;
    
    % Dividing the before ICA data in two datasets
    div = cvpartition(size(noise,1), 'Holdout', 0.5); % choose 50% of signals randomly
    ind = div.test; % return the indexes of 50% of choosing signals
    noise_training = noise(ind,:);
    noise_test = noise(~ind,:);
    number_events = size(noise_test,1); %quantidade de sinais no conjunto de teste

    % Estimating the mean of the training data
    mean_noise_training = mean(noise_training);

    % Applying ICA to the noise data of training
    [noise_ica, A, W] = fastica(noise_training', 'numOfIC', number_dimensions); % ICA function
    noise_ica = noise_ica'; % variables must be in columns

    % Normalizing the histograms of noise after ICA and finding their x coordinates
    hist_probabilities = -1*ones(bins, size(noise_ica,2));
    hist_bins = zeros(bins + 1, size(noise_ica,2));
    hist_coordinate_x = zeros(size(hist_bins, 1) - 1, number_dimensions);
    ica_probabilities_hist = gobjects(1, number_dimensions);
    for i = 1:number_dimensions
        % Plotting the normalized histograms
        ica_probabilities_hist(i) = figure;
        h = histogram(noise_ica(:, i), bins, 'Normalization', 'probability', ...
                      'FaceColor', '#DF65F8', 'EdgeColor', '#DF65F8');

        % Finding the bin edges and the values
        hist_probabilities(:, i) = h.Values;
        hist_bins(:, i) = h.BinEdges;

        % Finding the x coordinates
        for j = 1:size(hist_bins, 1) - 1
            hist_coordinate_x(j, i) = (hist_bins(j, i) + hist_bins(j + 1, i))/2;
        end

        % Using splines to interpolate
        spline_hist(i) = spline(hist_coordinate_x(:, i), hist_probabilities(:, i));

        % Plotting the interpolations
        hold on
        plot(hist_coordinate_x(:, i), ppval(hist_coordinate_x(:, i), spline_hist(i)), ...
             'Color', 'k', 'LineWidth', 1);
        legend({['variable ' int2str(i)], ['interpolation ' int2str(i)]}, 'Location', 'best');
        hold off
    end
    
    % Predefined structures
    s = [0  0.0172  0.4524  1  0.5633  0.1493  0.0424]; % normalized reference pulse
    OF2 = [-0.3781  -0.3572  0.1808  0.8125  0.2767  -0.2056  -0.3292];
    
    % Mounting the complete signal
    amplitude_true = exprnd(snr*mPu, number_events, 1);
    r = zeros(number_events, size(noise_test,2));
    for i = 1:number_events
        r(i,:) = amplitude_true(i)*pegaPulseJitter + noise_test(i,:); % complete signal in 7 dimensions
    end    
    
    % Estimating the amplitude using the linear methods
    % gaussian
    covariance_gauss = cov(noise_training); % covariance matrix of training data
    OF = (inv(covariance_gauss)*s')/(s*inv(covariance_gauss)*s');
    amplitude_gauss = (r - pedestal)*OF;
    % of2
    amplitude_of = r*OF2';
    % cof
    amplitude_cof = aplicaCOF(r - pedestal, 4.5);

    % Estimating the Gaussian PDF
    pdf_gauss = ones(number_events, 1);
    for i = 1:number_events
        pdf_gauss(i) = pdfGaussian(mean_noise_training, covariance_gauss, ...
                                   r(i,:), s, amplitude_gauss(i));
    end
    
    % Estimating the amplitude using MLE + ICA method
    amplitude_ica = amplitude_gauss;
    marginal_probability = zeros(1, number_dimensions);
    pdf_ica = ones(number_events, 1);
    for i = 1:number_events
        fprintf("Media do sinal = %d \nOcupacao = %d \nEvento = %d/%d \n", ...
                snr*mPu, oc, i, number_events);

        amplitude_ica(i) = amplitudeIca(r(i,:), s, mean_noise_training, W, amplitude_gauss(i), ...
                                        number_dimensions, marginal_probability, spline_hist);
        pdf_ica(i) = pdfIca(r(i,:), s,mean_noise_training, W, amplitude_gauss(i), ...
                            number_dimensions, marginal_probability, spline_hist);
    end

    % Estimating the chi2 of each method
    chi2_gauss = zeros(number_events, 1);
    chi2_ica = zeros(number_events, 1);
    for i = 1:number_events
        % gaussian
        chi2_gauss(i) = chi2EfficiencyEstimation(amplitude_gauss(i), r(i, :), s, pedestal);
        % ica
        chi2_ica(i) = chi2EfficiencyEstimation(amplitude_ica(i), r(i, :), s, pedestal);
    end
    
    % Estimating the error of each method
    error_gauss(:, 1) = amplitude_gauss - amplitude_true;
    error_of(:, 1) = amplitude_of - amplitude_true;
    error_cof(:, 1) = amplitude_cof - amplitude_true;
    error_ica(:, 1) = amplitude_ica - amplitude_true;

    % Estimating the mean of the errors
    indice = oc/10 + 1;
    mean_error_gauss(indice, 1) = mean(error_gauss);
    mean_error_of(indice, 1) = mean(error_of);
    mean_error_cof(indice, 1) = mean(error_cof);
    mean_error_ica(indice, 1) = mean(error_ica);

    % Estimating the standard deviation of the errors
    std_error_gauss(indice, 1) = std(error_gauss);
    std_error_of(indice, 1) = std(error_of);
    std_error_cof(indice, 1) = std(error_cof);
    std_error_ica(indice, 1) = std(error_ica);
end

return;

% Plotando os histogramas dos erros
histogram(error_gauss, 100, 'DisplayStyle', 'stairs', 'EdgeColor', 'r', 'LineWidth', 1.5);
hold on
histogram(error_of, 100, 'DisplayStyle', 'stairs', 'EdgeColor', 'g', 'LineWidth', 1.5);
hold on
histogram(error_cof, 100, 'DisplayStyle', 'stairs', 'EdgeColor', 'k', 'LineWidth', 1.5);
hold on
histogram(error_ica, 100, 'DisplayStyle', 'stairs', 'EdgeColor', 'm', 'LineWidth', 1.5);
hold off
xlim([-500 600]);
legend({'MLE Gaussiano', 'OF', 'COF', 'MLE ICA'}, 'Position', [0.17 0.7 0.1 0.2]);
title(['Histograma dos erros com ' int2str(number_dimensions) ' dimensões']);

% Plotting the error versus probability graphs
figure
scatter(error_gauss, pdf_gauss, 'MarkerEdgeColor', 'b', 'Marker', '.');
title(['MLE Gaussiano, ocupação ' int2str(oc) '%'], 'FontSize', 13);
xlabel('Erro (contagens de ADC)');
ylabel('Probabilidade');
figure
scatter(error_ica, pdf_ica, 'MarkerEdgeColor', 'r', 'Marker', '.');
title(['MLE + ICA, ocupação ' int2str(oc) '%'], 'FontSize', 13);
xlabel('Erro (contagens de ADC)');
ylabel('Probabilidade');

% Plotting the error versus chi2 graphs
figure
scatter(error_gauss, chi2_gauss, 'MarkerEdgeColor', 'b', 'Marker', '.');
title(['MLE Gaussiano, ocupação ' int2str(oc) '%'], 'FontSize', 13);
xlabel('Erro (contagens de ADC)');
ylabel('\chi^2');
figure
scatter(error_ica, chi2_ica, 'MarkerEdgeColor', 'r', 'Marker', '.');
title(['MLE + ICA, ocupação ' int2str(oc) '%'], 'FontSize', 13);
xlabel('Erro (contagens de ADC)');
ylabel('\chi^2');

% Plotting the mean and standard deviation graphs
% mean
figure
plot(occupancies, mean_error_gauss, 'Color', [0.6 0.6 0.6], 'Marker', '.', 'MarkerSize', 20, 'MarkerEdgeColor', [0 0.4470 0.7410]);
hold on
plot(occupancies, mean_error_of, 'Color', [0.6 0.6 0.6], 'Marker', '.', 'MarkerSize', 20, 'MarkerEdgeColor', [0.8500 0.3250 0.0980]);
hold on
plot(occupancies, mean_error_cof, 'Color', [0.6 0.6 0.6], 'Marker', '.', 'MarkerSize', 20, 'MarkerEdgeColor', [0.4940 0.1840 0.5560]);
hold on
plot(occupancies, mean_error_ica, 'Color', [0.6 0.6 0.6], 'Marker', '.', 'MarkerSize', 20, 'MarkerEdgeColor', [0.6350 0.0780 0.1840]);
hold off
title(['Média mPu' int2str(mPu) ' snr' int2str(snr)]);
legend({'Gaussian MLE', 'OF', 'COF', 'MLE + ICA'}, 'Position', [0.17 0.7 0.1 0.2]);
xlabel('Occupancy (%)');
ylabel('Mean of error (ADC counts)');
% standard deviation
figure
plot(occupancies, std_error_gauss, 'Color', [0.6 0.6 0.6], 'Marker', '.', 'MarkerSize', 20, 'MarkerEdgeColor', [0 0.4470 0.7410]);
hold on
plot(occupancies, std_error_of, 'Color', [0.6 0.6 0.6], 'Marker', '.', 'MarkerSize', 20, 'MarkerEdgeColor', [0.8500 0.3250 0.0980]);
hold on
plot(occupancies, std_error_cof, 'Color', [0.6 0.6 0.6], 'Marker', '.', 'MarkerSize', 20, 'MarkerEdgeColor', [0.4940 0.1840 0.5560]);
hold on
plot(occupancies, std_error_ica, 'Color', [0.6 0.6 0.6], 'Marker', '.', 'MarkerSize', 20, 'MarkerEdgeColor', [0.6350 0.0780 0.1840]);
hold off
title(['Desvio padrão mPu' int2str(mPu) ' snr' int2str(snr)]);
legend({'Gaussian MLE', 'OF', 'COF', 'MLE + ICA'}, 'Position', [0.17 0.7 0.1 0.2]);
xlabel('Occupancy (%)');
ylabel('Standard Deviation of error (ADC counts)');
