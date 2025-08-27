% metrics_stats.m
opts = detectImportOptions('captures/k8s_usage_12h.csv','Delimiter',',');
opts = setvartype(opts, {'iso8601','app','plane','cluster'}, 'string');
T = readtable('captures/k8s_usage_12h.csv', opts);

% Map app -> color
appCats = categories(categorical(T.app));
colors = zeros(numel(appCats),3);
for i = 1:numel(appCats)
    switch string(appCats{i})
        case "l2sm"
            colors(i,:) = [0 0.4470 0.7410]; % blue
        case "submariner"
            colors(i,:) = [1 0 0];           % red
        otherwise
            colors(i,:) = [0.5 0.5 0.5];     % gray fallback
    end
end

% Plot with filled boxes
figure;
h = boxchart(categorical(T.cluster), T.cpu_cores, ...
             'GroupByColor', categorical(T.app),'BoxWidth',2,'CapWidth',0,'LineWidth',1);

% Apply colors
for i = 1:numel(appCats)
    set(h(i), 'BoxFaceColor', colors(i,:), ...
              'BoxFaceAlpha', 0.5); % slightly transparent fill
end

xlabel('cluster'); ylabel('cpu cores');
title('CPU cores by cluster (fill color = app)');
legend(appCats, 'Location','best');
grid on;
tikz_boxplot(categorical(T.cluster), T.cpu_cores)
%matlab2tikz('captures/k8s_usage_12h.tex');
