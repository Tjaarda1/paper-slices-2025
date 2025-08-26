function plot_packet_counts(experiment, varargin)
% plot_packet_counts(experiment, Name,Value,...)
% Reads packet_counts.csv and plots Packets/s per (podBase, clusterId).
% Layout: a single vertical stack — one subplot per present (podBase, clusterId).
% The pair (toolbox-1, sub-managed-1) is excluded from display.
%
% INPUT:
%   experiment : either a captures/<stamp> folder name OR a full path to a folder
%
% NAME-VALUE (optional):
%   'PingStart'       (double, seconds)  default []
%   'PingDuration'    (double, seconds)  default []
%   'NmapStart'       (double, seconds)  default []
%   'NmapTimeout'     (double, seconds)  default []
%   'TikZFile'        (char/string)      default ""   % template/path; split files derive from this
%   'TikZStandalone'  (logical)          default false
%   'TikZWidth'       (char/string)      default '\textwidth'
%   'TikZAxisHeight'  (char/string)      default ''   % per-axis height; auto if empty
%
% EXAMPLE:
%   plot_packet_counts('20250825_101112','PingStart',5,'PingDuration',10,...
%       'NmapStart',20,'NmapTimeout',150,'TikZFile','packet_counts.tex');

    % ---- args / defaults
    p = inputParser;
    addOptional(p,'experiment',pwd,@(s)ischar(s)||isstring(s));
    addParameter(p,'PingStart',   [], @(x) isempty(x) || (isnumeric(x)&&isscalar(x)));
    addParameter(p,'PingDuration',[], @(x) isempty(x) || (isnumeric(x)&&isscalar(x)));
    addParameter(p,'NmapStart',   [], @(x) isempty(x) || (isnumeric(x)&&isscalar(x)));
    addParameter(p,'NmapTimeout', [], @(x) isempty(x) || (isnumeric(x)&&isscalar(x)));

    % TikZ options
    addParameter(p,'TikZFile',        "",    @(s)ischar(s)||isstring(s));
    addParameter(p,'TikZStandalone',  false, @(b)islogical(b)&&isscalar(b));
    addParameter(p,'TikZWidth',       '\textwidth', @(s)ischar(s)||isstring(s));
    addParameter(p,'TikZAxisHeight',  "",    @(s)ischar(s)||isstring(s));

    parse(p, experiment, varargin{:});
    opt = p.Results;

    % ---- resolve folder
    base = char(opt.experiment);
    if isfolder(fullfile('captures', base))
        directory = fullfile('captures', base);
    elseif isfolder(base)
        directory = base;
    else
        error('Folder not found: %s (nor captures/%s)', base, base);
    end

    csvFile = fullfile(directory, 'packet_counts.csv');
    if ~isfile(csvFile)
        error('Missing file: %s', csvFile);
    end

    % ---- Load CSV
    T = readtable(csvFile, 'TextType','string');
    must = ["pod","second","count"];
    assert(all(ismember(must, string(T.Properties.VariableNames))), ...
        'CSV missing required columns (need pod, second, count).');

    % numeric
    T.second = double(T.second);
    T.count  = double(T.count);

    % ---- Split pod into base & cluster
    % Expect names like "toolbox-0-sub-managed-1"
    toks = regexp(T.pod, '^(toolbox-\d+)-(.*)$', 'tokens', 'once');
    podBase   = strings(height(T),1);
    clusterId = strings(height(T),1);
    for i = 1:height(T)
        if ~isempty(toks{i})
            podBase(i)   = string(toks{i}{1});
            clusterId(i) = string(toks{i}{2});
        else
            % fallback: no match, treat entire pod as base, cluster = "unknown"
            podBase(i)   = T.pod(i);
            clusterId(i) = "unknown";
        end
    end
    T.podBase   = podBase;
    T.clusterId = clusterId;

    % Natural order for bases: toolbox-0, toolbox-1, ...
    bases = unique(T.podBase, 'stable');
    nums  = str2double(extract(bases, digitsPattern));   % pulls the N from "toolbox-N"
    if all(~isnan(nums))
        [~, ord] = sort(nums);
        bases = bases(ord);
    end

    % Stable order for clusters
    clusters = unique(T.clusterId, 'stable');

    % ---- Build present (base, cluster) pairs and filter out the unwanted one
    pairs = unique(T(:, ["podBase","clusterId"]), 'rows', 'stable');
    % Exclude toolbox-1 from sub-managed-1
    bad = pairs.podBase == "toolbox-1" & pairs.clusterId == "sub-managed-1";
    pairs = pairs(~bad, :);

    if isempty(pairs)
        warning('No (podBase, clusterId) pairs to display after filtering.');
        return;
    end

    % Sort pairs by base (natural) then cluster (stable)
    [~, ib] = ismember(pairs.podBase, bases);
    [~, ic] = ismember(pairs.clusterId, clusters);
    [~, order] = sortrows([ib(:) ic(:)], [1 2]);
    pairs = pairs(order, :);

    % Duration & x-axis
    dur = max(T.second) + 1;
    x = 0:dur-1;

    % ---- Figure (vertical stack preview)
    N = height(pairs);
    axHandles = gobjects(N,1);
    figure('Color','w','Position',[80 80 1200 max(300, 200 + 220*N)]);
    sgtitle(sprintf('Packets/s — %s', directory), 'Interpreter','none');

    for k = 1:N
        baseK    = pairs.podBase(k);
        clusterK = pairs.clusterId(k);
        ax = subplot(N, 1, k);
        axHandles(k) = ax;

        y = seriesFrom(T, baseK, clusterK, dur);
        plot(x, y, '-'); grid on; box off;
        xlim([x(1) x(end)]);
        yMax = 50;
        ylim([0 yMax*1.05]);

        if k==N, xlabel('Time (s)'); end
        ylabel('Packets/s');

        % Optional shading for ping / nmap
        hold on;
        yl = ylim;
        if ~isempty(opt.PingStart) && ~isempty(opt.PingDuration)
            xs = [opt.PingStart, opt.PingStart+opt.PingDuration];
            patch([xs(1) xs(2) xs(2) xs(1)], [yl(1) yl(1) yl(2) yl(2)], ...
                  [0.85 0.95 1.00], 'EdgeColor','none', 'FaceAlpha',0.35); % light blue
        end
        if ~isempty(opt.NmapStart) && ~isempty(opt.NmapTimeout)
            xs = [opt.NmapStart, opt.NmapStart+opt.NmapTimeout];
            patch([xs(1) xs(2) xs(2) xs(1)], [yl(1) yl(1) yl(2) yl(2)], ...
                  [0.95 0.85 0.85], 'EdgeColor','none', 'FaceAlpha',0.25); % light red
        end
        uistack(findobj(ax,'Type','line'),'top'); % keep the line on top
        hold off;
    end

    % ---- Split TikZ export: one .tex per subplot -----------------------------
    if ~isempty(opt.TikZFile)
        if exist('matlab2tikz','file') ~= 2
            error(['matlab2tikz not found on the MATLAB path.\n' ...
                   'Install it and ensure matlab2tikz.m is reachable.']);
        end

        % Derive output directory + base name from TikZFile
        [outDir, baseName, ~] = fileparts(char(opt.TikZFile));
        if isempty(outDir), outDir = directory; end
        if isempty(baseName), baseName = 'packet_counts'; end
        if ~exist(outDir, 'dir'), mkdir(outDir); end

        % Per-axis size
        if strlength(string(opt.TikZAxisHeight)) > 0
            axisHeight = char(opt.TikZAxisHeight);
        else
            % nice default per-axis height for typical N=3
            axisHeight = sprintf('%.3f\\textheight', max(0.10, min(0.28, 0.78/max(N,1))));
        end
        titleY = '1.0ex'; % lift titles a touch
        extraAxis = { ...
            'grid=both', ...
            'tick align=outside', ...
            'scaled y ticks=true', ...
            ['title style={yshift=', titleY, '}'] ...
        };

        for k = 1:N
            baseK    = char(pairs.podBase(k));
            clusterK = char(pairs.clusterId(k));
            figk = figure('Visible','off','Color','w', 'Position',[100 100 1000 420]);
            % copy that subplot into its own figure
            newAx = copyobj(axHandles(k), figk);
            set(newAx, 'Units','normalized', 'Position',[0.13 0.15 0.775 0.75]);

            % sanitize file name
            tag = sanitize_for_filename(sprintf('%s--%s', baseK, clusterK));
            outFile = fullfile(outDir, sprintf('%s_%02d_%s.tex', baseName, k, tag));

            try
                cleanfigure;
            catch
                % ok if not available
            end
            matlab2tikz(outFile, ...
                'standalone',  logical(opt.TikZStandalone), ...
                'height',      axisHeight, ...
                'width',       char(opt.TikZWidth), ...
                'extraAxisOptions', extraAxis ...
            );
            fprintf('[✓] TikZ saved: %s\n', outFile);
            close(figk);
        end
    end

    % Optional: export as PDF instead
    % print(fullfile(directory,'packet_counts_vertical.pdf'), '-dpdf', '-painters');
end

function y = seriesFrom(T, base, cluster, dur)
% Build a durx1 vector of counts per second for (podBase==base & clusterId==cluster)
    mask = strcmp(T.podBase, base) & strcmp(T.clusterId, cluster);
    if ~any(mask)
        y = zeros(dur,1);
        return;
    end
    sec = T.second(mask);
    cnt = T.count(mask);
    % guard
    sec = sec(~isnan(sec) & sec>=0 & sec<dur);
    cnt = cnt(1:numel(sec));
    y = accumarray(sec+1, cnt, [dur 1], @sum, 0);
end

function s = sanitize_for_filename(s)
% Lowercase, replace non [A-Za-z0-9_-] with underscores, collapse repeats.
    s = lower(char(s));
    s = regexprep(s,'[^\w\-]+','_');
    s = regexprep(s,'_+','_');
    s = regexprep(s,'^_+|_+$','');
end
