function analyze_setup_time(csvPath)
% analyze_setup_time  Compute summary stats for L2SM setup-time runs.
% Usage:
%   analyze_setup_time                    % uses default CSV path
%   analyze_setup_time('path/to/setup_time.csv')

    if nargin < 1 || isempty(csvPath)
        csvPath = 'experiments/setuptime/l2sm/captures/setup_time.csv';
    end
    if ~isfile(csvPath)
        error('CSV not found: %s', csvPath);
    end

    % Read CSV -> table
    opts = detectImportOptions(csvPath, 'Delimiter', ',');
    % Ensure IPs are read as text
    ipCols = {'src_ping_ip','dst_pong_ip'};
    for k = 1:numel(ipCols)
        if any(strcmp(opts.VariableNames, ipCols{k}))
            opts = setvartype(opts, ipCols{k}, 'string');
        end
    end
    T = readtable(csvPath, opts);

    % Column aliases (MATLAB auto-renames headers; these should match)
    mustHave = {'run','apply_epoch_ns','first_icmp_epoch_ns_pong', ...
                'approx_offset_ns','first_icmp_epoch_ns_laptop', ...
                'probe_period_ms','estimate_ms','error_bound_ms'};
    for k = 1:numel(mustHave)
        if ~any(strcmp(T.Properties.VariableNames, mustHave{k}))
            error('Missing column "%s" in %s', mustHave{k}, csvPath);
        end
    end

    % Extract series (ms)
    x = double(T.estimate_ms);
    eb = double(T.error_bound_ms);           % per-run ±P/2
    Pms = double(T.probe_period_ms);
    n = sum(isfinite(x));

    if n == 0
        error('No finite estimate_ms values found.');
    end

    % Core stats (omit NaNs)
    mean_ms   = mean(x, 'omitnan');                 % sample mean
    std_ms    = std(x,  'omitnan');                 % sample std (n-1)
    median_ms = median(x, 'omitnan');
    min_ms    = min(x, [], 'omitnan');
    max_ms    = max(x, [], 'omitnan');
    iqr_ms    = iqr(x);

    prc = prctile(x, [50 90 95 99]);
    p50_ms = prc(1);
    p90_ms = prc(2);
    p95_ms = prc(3);
    p99_ms = prc(4);

    % A few helpful extras
    mad_ms = mad(x, 1);                           % mean abs dev about median
    % Aggregate error-bound intuition (median of per-run bounds)
    eb_med_ms = median(eb, 'omitnan');

    % Print summary
    fprintf('\n===== Setup-Time Summary (%s) =====\n', csvPath);
    fprintf('n                     : %d\n', n);
    fprintf('probe_period_ms (mode): %.3g (unique values: %s)\n', mode(Pms), uniqueList(Pms));
    fprintf('mean_ms               : %.3f\n', mean_ms);
    fprintf('std_ms                : %.3f\n', std_ms);
    fprintf('median_ms (p50)       : %.3f\n', median_ms);
    fprintf('p90_ms                : %.3f\n', p90_ms);
    fprintf('p95_ms                : %.3f\n', p95_ms);
    fprintf('p99_ms                : %.3f\n', p99_ms);
    fprintf('min_ms / max_ms       : %.3f / %.3f\n', min_ms, max_ms);
    fprintf('IQR_ms                : %.3f\n', iqr_ms);
    fprintf('MAD_ms                : %.3f\n', mad_ms);
    fprintf('median_error_bound_ms : %.3f  (per-run bound ≈ ±P/2)\n', eb_med_ms);

    % Write one-row summary CSV & JSON next to input
    outDir = fileparts(csvPath);
    summaryTbl = table( ...
        n, mean_ms, std_ms, median_ms, p90_ms, p95_ms, p99_ms, ...
        min_ms, max_ms, iqr_ms, mad_ms, eb_med_ms, ...
        'VariableNames', {'n','mean_ms','std_ms','median_ms','p90_ms','p95_ms','p99_ms', ...
                          'min_ms','max_ms','iqr_ms','mad_ms','median_error_bound_ms'});
    outCsv = fullfile(outDir, 'setup_time_summary.csv');
    outJson = fullfile(outDir, 'setup_time_summary.json');
    writetable(summaryTbl, outCsv);

    S = table2struct(summaryTbl);
    fid = fopen(outJson, 'w'); fprintf(fid, '%s', jsonencode(S)); fclose(fid);

    % Optional plots (uncomment if desired)
    %{
    figure('Name','Setup-Time Distribution');
    histogram(x, 'BinMethod','fd'); xlabel('estimate\_ms'); ylabel('count'); title('Histogram of setup times');

    figure('Name','Setup-Time ECDF');
    [f,xx] = ecdf(x);
    plot(xx, f, 'LineWidth', 1.5); grid on;
    xlabel('estimate\_ms'); ylabel('F(x)'); title('Empirical CDF');
    %}

    fprintf('\nSaved summary to:\n  %s\n  %s\n\n', outCsv, outJson);

    % For programmatic use, return variables when called with output
    if nargout > 0
        varargout{1} = summaryTbl; %#ok<NASGU>
    end
end

function s = uniqueList(v)
    v = v(:);
    u = unique(v(~isnan(v)));
    if numel(u) > 6
        s = sprintf('%.0f(ms)x%d + ...', mode(v), numel(u));
    else
        s = strjoin(string(u.'), ',');
    end
end
