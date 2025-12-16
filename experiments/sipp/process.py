import pandas as pd
import sys

# Replace 'data.csv' with your actual csv filename if different
FILENAME = 'data.csv'

def generate_latex_plot(filename):
    try:
        # Read the CSV file
        # The separator is a semi-colon based on your example
        df = pd.read_csv(filename, sep=';')
        
        # Clean up column names (remove potential extra spaces)
        df.columns = [c.strip() for c in df.columns]
        
        # Check if necessary columns exist
        required_columns = ['ElapsedTime(C)', 'CallRate(P)', 'TargetRate']
        for col in required_columns:
            if col not in df.columns:
                print(f"Error: Column '{col}' not found in CSV.")
                return

        # Function to convert HH:MM:SS to seconds
        def time_to_seconds(t_str):
            try:
                h, m, s = map(int, t_str.strip().split(':'))
                return h * 3600 + m * 60 + s
            except:
                return -1

        # Create a 'seconds' column for the x-axis
        # We use ElapsedTime(C) (Cumulative) as it increments correctly in your data
        df['seconds'] = df['ElapsedTime(C)'].apply(time_to_seconds)

        # Filter the data for the first 100 seconds
        df_plot = df[(df['seconds'] >= 0) & (df['seconds'] <= 100)].sort_values('seconds')

        if df_plot.empty:
            print("No data found for the first 100 seconds.")
            return
            
        # --- Generate LaTeX Output ---
        
        print("% --- Start of Python Script Output ---")
        print("% Note: Your data values are around 1000.") 
        print("% Please update ymax in your axis environment (e.g., ymax=1100).")
        print("")

        # 1. Call Rate Plot
        print(r"% Plotting CallRate(P)")
        print(r"\addplot [color=mycolor3, thick, mark=*, mark size=1.0pt]")
        print(r"  table[row sep=crcr]{%")
        print(r"x    y\\")
        for _, row in df_plot.iterrows():
            # Print x (seconds) and y (CallRate)
            print(f"{int(row['seconds'])}    {row['CallRate(P)']}\\\\")
        print(r"};")
        print(r"\addlegendentry{Call Rate (P)}")
        print("")

        # 2. Target Rate Plot
        print(r"% Plotting TargetRate")
        print(r"\addplot [color=red, dashed, thick]")
        print(r"  table[row sep=crcr]{%")
        print(r"x    y\\")
        for _, row in df_plot.iterrows():
            # Print x (seconds) and y (TargetRate)
            print(f"{int(row['seconds'])}    {row['TargetRate']}\\\\")
        print(r"};")
        print(r"\addlegendentry{Target Rate}")
        print("% --- End of Python Script Output ---")

    except FileNotFoundError:
        print(f"Error: The file '{filename}' was not found.")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    generate_latex_plot(FILENAME)
