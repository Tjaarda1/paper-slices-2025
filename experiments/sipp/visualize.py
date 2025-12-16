import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import io

# ---------------------------------------------------------
# 1. Load Data
# ---------------------------------------------------------
# Paste your data here or read from a file using pd.read_csv('filename.csv', sep=';')

df = pd.read_csv('data.csv', sep=';', index_col=False)

# ---------------------------------------------------------
# 2. Parse Custom Formats
# ---------------------------------------------------------

# Helper: Parse "HH:MM:SS:microseconds"
def parse_duration(t_str):
    try:
        if pd.isna(t_str): return 0.0
        parts = t_str.split(':')
        if len(parts) == 4:
            return int(parts[0])*3600 + int(parts[1])*60 + int(parts[2]) + int(parts[3])/1e6
        return 0.0
    except:
        return 0.0

# Helper: Parse "YYYY-MM-DD HH:MM:SS.micros epoch"
def parse_datetime(dt_str):
    try:
        # Extract the standard datetime part (first two tokens)
        parts = dt_str.split()
        return pd.to_datetime(f"{parts[0]} {parts[1]}")
    except:
        return pd.NaT

df['ParsedTime'] = df['CurrentTime'].apply(parse_datetime)
df['ResponseTime_ms'] = df['ResponseTime1(C)'].apply(parse_duration) * 1000
df['CallLength_ms'] = df['CallLength(C)'].apply(parse_duration) * 1000

# ---------------------------------------------------------
# 3. Plotting
# ---------------------------------------------------------
plt.style.use('ggplot')
fig, axes = plt.subplots(2, 2, figsize=(14, 10))
fig.suptitle('SIP Performance Metrics', fontsize=16)

# Plot 1: Call Rates
ax1 = axes[0, 0]
ax1.plot(df['ParsedTime'], df['CallRate(C)'], label='CallRate(C)', marker='o')
ax1.plot(df['ParsedTime'], df['TargetRate'], label='TargetRate', linestyle='--')
ax1.set_title('Call Rate over Time')
ax1.set_ylabel('Rate (cps)')
ax1.legend()
ax1.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
ax1.tick_params(axis='x', rotation=30)

# Plot 2: Interval Counts (P = Period)
ax2 = axes[0, 1]
ax2.plot(df['ParsedTime'], df['SuccessfulCall(P)'], label='Successful(P)', marker='o', color='green')
ax2.plot(df['ParsedTime'], df['FailedCall(P)'], label='Failed(P)', marker='x', color='red')
ax2.set_title('Interval Activity (Counts per Period)')
ax2.set_ylabel('Count')
ax2.legend()
ax2.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
ax2.tick_params(axis='x', rotation=30)

# Plot 3: Latency & Duration
ax3 = axes[1, 0]
ax3.plot(df['ParsedTime'], df['ResponseTime_ms'], label='Response Time (Avg)', marker='o')
ax3.plot(df['ParsedTime'], df['CallLength_ms'], label='Call Length (Avg)', marker='s')
ax3.set_title('Average Duration (Cumulative)')
ax3.set_ylabel('Time (ms)')
ax3.legend()
ax3.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
ax3.tick_params(axis='x', rotation=30)

# Plot 4: Response Time Histogram (Last Snapshot)
ax4 = axes[1, 1]
hist_cols = [c for c in df.columns if 'ResponseTimeRepartition1_' in c and c != 'ResponseTimeRepartition1']

# Sort columns by limit value
def get_limit(name):
    try:
        return int(name.split('<')[1])
    except:
        return 99999 # Handle >= cases
        
hist_cols.sort(key=get_limit)

if not df.empty:
    last_row = df.iloc[-1]
    values = last_row[hist_cols]
    labels = [c.replace('ResponseTimeRepartition1_', '') for c in hist_cols]
    
    ax4.bar(labels, values, color='skyblue', edgecolor='black')
    ax4.set_title('Response Time Distribution (Final Snapshot)')
    ax4.set_ylabel('Count')
    ax4.set_xlabel('Bucket (ms)')
    ax4.tick_params(axis='x', rotation=45)

plt.tight_layout(rect=[0, 0.03, 1, 0.95])
plt.savefig('sip_metrics.png')
plt.show()
