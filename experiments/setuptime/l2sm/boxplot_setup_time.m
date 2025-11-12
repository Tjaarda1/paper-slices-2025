function boxplot_setup_time(csvPath)
% boxplot_setup_time  Draw a boxplot for setup time (estimate_ms).
% Usage:
%   boxplot_setup_time                               % default path
%   boxplot_setup_time('experiments/.../setup_time.csv')

    if nargin < 1 || isempty(csvPath)
        csvPath = 'experiments/setuptime/l2sces/captures/setup_time.csv';
    end
    if ~isfile(csvPath)
        error('CSV not found: %s', csvPath);
    end

    % Read CSV
    opts = detectImportOptions(csvPath,'Delimiter',',');
    T = readtable(csvPath, opts);

    x = double(T.estimate_ms);
    x = x(isfinite(x));

    if isempty(x)
        error('No finite estimate_ms values found.');
    end

    % Stats for title
    n = numel(x);
    med = median(x,'omitnan');
    p90 = prctile(x,90);
    mu  = mean(x,'omitnan');

    % Boxplot (single distribution)
    figure('Name','Setup Time Boxplot');
    boxplot(x,'Notch','on','Labels',{'setup time (ms)'});
    ylabel('milliseconds');
    title(sprintf('Setup time (n=%d)  median=%.2f ms, p90=%.2f ms, mean=%.2f ms', n, med, p90, mu));

    % Overlay jittered points and mean marker (optional; comment out if you want only the box)
    hold on;
    jitter = (rand(size(x))-0.5)*0.15;   % small horizontal jitter
    scatter(1 + jitter, x, 10, 'filled', 'MarkerFaceAlpha', 0.25);
    plot(1, mu, 'kd', 'MarkerFaceColor', 'k', 'MarkerSize', 6);
    hold off;

    % Save next to CSV
    outPng = fullfile(fileparts(csvPath), 'setup_time_boxplot.png');
    saveas(gcf, outPng);
    fprintf('Saved boxplot to: %s\n', outPng);
end
