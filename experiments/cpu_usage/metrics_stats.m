% === metrics_stats.m ===
% Print numeric variability stats and save CSVs (no toolboxes required)

% -------- Load --------
opts = detectImportOptions('captures/k8s_usage_12h.csv','Delimiter',',');
opts = setvartype(opts, {'iso8601','app','plane','cluster'}, 'string');
T = readtable('captures/k8s_usage_12h.csv', opts);

% Ensure numeric target
if ~isnumeric(T.cpu_cores), T.cpu_cores = double(T.cpu_cores); end

% -------- Compute numbers --------
S_ca = group_stats(T, {'cluster','app'});
S_c  = group_stats(T, {'cluster'});
S_a  = group_stats(T, {'app'});

% -------- Print nicely --------
disp('--- Variability per CLUSTER × APP ---'); disp(round_table(S_ca,3));
disp('--- Variability per CLUSTER ---------'); disp(round_table(S_c, 3));
disp('--- Variability per APP -------------'); disp(round_table(S_a, 3));

% -------- Save CSVs --------
writetable(S_ca, 'captures/k8s_usage_12h_stats_cluster_app.csv');
writetable(S_c,  'captures/k8s_usage_12h_stats_cluster.csv');
writetable(S_a,  'captures/k8s_usage_12h_stats_app.csv');

%% ===== Local functions (keep below script for max compatibility) =====
function S = group_stats(tbl, groupVars)
    % Build cell array of grouping inputs (categoricals are robust for strings)
    args = cellfun(@(v) categorical(tbl.(v)), groupVars, 'UniformOutput', false);

    % Group index
    G = findgroups(args{:});

    % Reconstruct the key columns for each group using a representative value
    keyCols = cell(1, numel(groupVars));
    for k = 1:numel(groupVars)
        keyCols{k} = splitapply(@(z) z(1), args{k}, G);
    end
    S = table(keyCols{:}, 'VariableNames', groupVars);

    % Response variable
    y = tbl.cpu_cores;

    % Stats (all NaN-safe)
    S.N      = splitapply(@(z) sum(~isnan(z)), y, G);
    S.mean   = splitapply(@mean_nn,   y, G);
    S.std    = splitapply(@std_nn,    y, G);
    S.median = splitapply(@med_nn,    y, G);
    S.iqr    = splitapply(@iqr_nn,    y, G);
    S.min    = splitapply(@min_nn,    y, G);
    S.max    = splitapply(@max_nn,    y, G);
    S.p5     = splitapply(@(z) pct(z,5),   y, G);
    S.p95    = splitapply(@(z) pct(z,95),  y, G);
    S.mad1   = splitapply(@mad1_nn,   y, G);

    % Derived variability metrics
    S.CV     = S.std ./ S.mean;
    S.RCV    = S.iqr ./ S.median;
end

function TT = round_table(TT, ndp)
    vn = TT.Properties.VariableNames;
    for k = 1:numel(vn)
        if isnumeric(TT.(vn{k})), TT.(vn{k}) = round(TT.(vn{k}), ndp); end
    end
end

% ===== helpers without toolboxes =====
function m = mean_nn(x), x = x(~isnan(x)); if isempty(x), m = NaN; else, m = mean(x); end, end
function s = std_nn(x),  x = x(~isnan(x)); if isempty(x), s = NaN; else, s = std(x);  end, end
function v = min_nn(x),  x = x(~isnan(x)); if isempty(x), v = NaN; else, v = min(x);  end, end
function v = max_nn(x),  x = x(~isnan(x)); if isempty(x), v = NaN; else, v = max(x);  end, end
function p = pct(x,q)
    x = x(~isnan(x)); if isempty(x), p = NaN(size(q)); return; end
    x = sort(x); n = numel(x);
    r = (q/100).*(n-1) + 1;        % linear interpolation percentile
    rl = floor(r); rh = ceil(r); w = r - rl;
    p = (1-w).*x(rl) + w.*x(rh);
end
function v = med_nn(x), x = x(~isnan(x)); if isempty(x), v = NaN; else, v = median(x); end, end
function v = iqr_nn(x), v = pct(x,75) - pct(x,25); end
function v = mad1_nn(x)
    x = x(~isnan(x)); if isempty(x), v = NaN; else, v = median(abs(x - median(x))); end
end
