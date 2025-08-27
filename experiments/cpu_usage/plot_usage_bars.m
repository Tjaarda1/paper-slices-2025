% metrics_stats.m
opts = detectImportOptions('captures/k8s_usage_12h.csv','Delimiter',',');
opts = setvartype(opts, {'iso8601','app','plane','cluster'}, 'string');
T = readtable('captures/k8s_usage_12h.csv', opts);

% --- BAR PLOT: mean CPU usage by app & plane ---
G = groupsummary(T, {'app','plane'}, 'mean', 'cpu_cores');  % -> mean_cpu_cores

pairs  = ["submariner","control";
          "submariner","managed";
          "l2sm","control";
          "l2sm","managed"];
labels = ["submariner-control","submariner-managed","l2sm-control","l2sm-managed"];

y = nan(1,4);
for k = 1:4
    idx = (string(G.app)==pairs(k,1) & string(G.plane)==pairs(k,2));
    if any(idx), y(k) = G.mean_cpu_cores(idx); end
end

% Make categorical to force order
x = categorical(labels, labels, 'Ordinal', true);

% Colors
c_sub = [15 214 162]/255; % #0FD6A2
c_l2  = [15 158 213]/255; % #0F9ED5

% Split into two series so TikZ keeps fills per app
y_sub = [y(1) y(2) NaN NaN];
y_l2  = [NaN NaN y(3) y(4)];

% Give the axis a little headroom
figure('Color','w');
hold on;
b1 = bar(x, y_sub, 'FaceColor', c_sub, 'DisplayName','submariner');
b2 = bar(x, y_l2,  'FaceColor', c_l2,  'DisplayName','l2sm');
hold off;

ylabel('CPU usage (cores)');
xlabel('Instance');
title('Mean CPU usage: submariner vs l2sm (control/managed)');
grid on;
legend('Location','northeast');

% Export to TikZ
% --- Export to TikZ ---
if ~exist('captures','dir'), mkdir('captures'); end
texfile = fullfile('captures','k8s_usage_12h.tex');
matlab2tikz(texfile, ...
  'standalone', false, ...
  'showInfo', false, ...
  'extraAxisOptions', { ...
     'ybar','bar width=18pt','bar shift=0pt', ...
     'xtick={submariner-control,submariner-managed,l2sm-control,l2sm-managed}', ...
     'enlarge x limits=0.3','clip=false' ...
  });
