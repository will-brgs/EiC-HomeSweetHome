import joblib
import os
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import classification_report, roc_auc_score

# ---------- helper functions ----------

def _clean_money_series(s: pd.Series) -> pd.Series:
    """
    Convert a money-like series such as "$1,234.56" to float.
    Leaves NaNs as NaN. Works even if some entries are already numeric.
    """
    if pd.api.types.is_numeric_dtype(s):
        return s.astype(float)

    return (
        s.astype(str)
         .str.replace(r'[\$,]', '', regex=True)
         .str.strip()
         .replace({'': np.nan, 'nan': np.nan, 'None': np.nan})
         .astype(float)
    )

def _clean_datetime_series(s: pd.Series) -> pd.Series:
    """
    Convert a date-like string series to pandas datetime.
    Uses errors='coerce' so bad values become NaT instead of crashing.
    """
    return pd.to_datetime(s, errors='coerce')

def _zip5_series(s: pd.Series) -> pd.Series:
    """
    Extract the first 5 digits of a ZIP (e.g., '63122-4001' -> '63122').
    Keeps NaNs as NaN.
    """
    return (
        s.astype(str)
         .str.extract(r'(\d{5})')[0]
         .where(lambda x: x.notna(), np.nan)
    )

def _clean_birth_year(s: pd.Series) -> pd.Series:
    """
    Convert Birth Year to numeric (float). Non-convertible becomes NaN.
    """
    return pd.to_numeric(s, errors='coerce')




def load_and_clean_all(
    monthly_path: str = "MonthlyDonorsData.csv",
    retention_path: str = "RetentionData.csv",
    transactions_path: str = "TransactionsToPresentData.csv",
):
    """
    Load and clean the three donor CSVs:
      - MonthlyDonorsData.csv
      - RetentionData.csv
      - TransactionsToPresentData.csv

    Returns:
      monthly_clean, retention_clean, transactions_clean (three DataFrames)
    """

    monthly = pd.read_csv(monthly_path)
    retention = pd.read_csv(retention_path)
    transactions = pd.read_csv(transactions_path)

    # --- define money/date columns for each file ---
    # 1) Monthly donors
    monthly_money_cols = [
        "Lifetime Revenue",
        "Latest Transaction Amount",
        "Projected Revenue (Fiscal Year)",
        "First Transaction Amount",
        "Largest Transaction Amount",
        "Lifetime Raised",
    ]
    monthly_date_cols = [
        "Latest Transaction Date",
        "Created Date",
        "First Transaction Date",
        "Largest Transaction Date",
        "Last Modified Date",
    ]

    # 2) Retention data
    retention_money_cols = [
        "First Transaction Amount",
        "Largest Transaction Amount",
        "Last Year Fundraised",
        "Last Year Raised",
        "Last Year Revenue",
        "Latest Transaction Amount",
        "Lifetime Fundraised",
        "Lifetime Raised",
        "Lifetime Revenue",
        "Year-to-Date Fundraised",
        "Year-To-Date Raised",
        "Year-To-Date Revenue",
    ]
    retention_date_cols = [
        "First Transaction Date",
        "Largest Transaction Date",
        "Latest Transaction Date",
    ]

    # 3) Transactions data
    transactions_money_cols = [
        "Amount",
        "Largest Transaction Amount",
        "Last Year Raised",
        "Latest Transaction Amount",
        "Lifetime Revenue",
    ]
    transactions_date_cols = [
        "Date",
        "Largest Transaction Date",
        "Last Modified Date",
        "Latest Transaction Date",
    ]

    # --- clean MonthlyDonorsData ---
    for col in monthly_money_cols:
        if col in monthly.columns:
            monthly[col + "_num"] = _clean_money_series(monthly[col])

    for col in monthly_date_cols:
        if col in monthly.columns:
            monthly[col + "_dt"] = _clean_datetime_series(monthly[col])

    if "Primary ZIP Code" in monthly.columns:
        monthly["Primary ZIP 5"] = _zip5_series(monthly["Primary ZIP Code"])
    if "Birth Year" in monthly.columns:
        monthly["Birth Year_num"] = _clean_birth_year(monthly["Birth Year"])

    # --- clean RetentionData ---
    for col in retention_money_cols:
        if col in retention.columns:
            retention[col + "_num"] = _clean_money_series(retention[col])

    for col in retention_date_cols:
        if col in retention.columns:
            retention[col + "_dt"] = _clean_datetime_series(retention[col])

    if "Primary ZIP Code" in retention.columns:
        retention["Primary ZIP 5"] = _zip5_series(retention["Primary ZIP Code"])
    if "Birth Year" in retention.columns:
        retention["Birth Year_num"] = _clean_birth_year(retention["Birth Year"])

    # --- clean TransactionsToPresentData ---
    for col in transactions_money_cols:
        if col in transactions.columns:
            transactions[col + "_num"] = _clean_money_series(transactions[col])

    for col in transactions_date_cols:
        if col in transactions.columns:
            transactions[col + "_dt"] = _clean_datetime_series(transactions[col])

    if "Primary ZIP Code" in transactions.columns:
        transactions["Primary ZIP 5"] = _zip5_series(transactions["Primary ZIP Code"])
    if "Birth Year" in transactions.columns:
        transactions["Birth Year_num"] = _clean_birth_year(transactions["Birth Year"])

    # --- convert some categorical columns to 'category' dtype ---
    for df, cat_cols in [
        (monthly, ["Gender", "Groups", "Volunteer", "Board Member", "Employer", "Primary State"]),
        (retention, ["Gender", "Groups", "Home Owner", "Board Member", "Employer",
                     "Primary State"]),
        (transactions, ["Status", "Campaign", "Appeal", "Fund", "Has Tribute",
                        "Type", "Groups", "Young Friends Council", "Volunteer",
                        "Board Member", "Employer", "Gender", "Primary State"]),
    ]:
        for c in cat_cols:
            if c in df.columns:
                df[c] = df[c].astype("category")

    return monthly, retention, transactions



def build_snapshot_churn_dataset(
    monthly_df,
    retention_df,
    transactions_df,
    prediction_window_days: int = 90,
    snapshot_freq: str = "30D",
    min_history_days: int = 90,
    active_recency_max: int = 90,
):
    """
    Build a leakage-free churn dataset using time snapshots.

    For each donor and each snapshot date:
      - Features are computed only from transactions on or before the snapshot_date.
      - Label is determined by donations in the NEXT `prediction_window_days` after snapshot_date.

    Label definition:
      churn_label = 1 if no donations between (snapshot_date, snapshot_date + prediction_window_days]
      churn_label = 0 otherwise.

    Additional filter:
      - Only keep snapshots where the donor is still "active" at snapshot_date, i.e.
        recency_days <= active_recency_max.
    """
    tx = transactions_df.copy()

    # Ensure date and columns are cleaned
    if "Date_dt" in tx.columns:
        date_col = "Date_dt"
    else:
        tx["Date_dt"] = pd.to_datetime(tx["Date"], errors="coerce")
        date_col = "Date_dt"

    if "Amount_num" in tx.columns:
        amt_col = "Amount_num"
    else:
        tx["Amount_num"] = (
            tx["Amount"]
              .astype(str)
              .str.replace(r'[\$,]', '', regex=True)
              .replace({'': np.nan, 'nan': np.nan})
              .astype(float)
        )
        amt_col = "Amount_num"

    tx = tx[tx[date_col].notna()].copy()

    min_date = tx[date_col].min()
    max_date = tx[date_col].max()

    snapshot_start = min_date + pd.Timedelta(days=min_history_days)
    snapshot_end = max_date - pd.Timedelta(days=prediction_window_days)

    if snapshot_start >= snapshot_end:
        raise ValueError("Not enough time span in data for the chosen min_history_days and prediction_window_days.")

    snapshot_dates = pd.date_range(start=snapshot_start, end=snapshot_end, freq=snapshot_freq)

    rows = []

    # Group transactions by account for faster per-account iteration
    grouped = tx.sort_values(date_col).groupby("Account Number")

    for account_id, df_acc in grouped:
        df_acc = df_acc.sort_values(date_col)

        # For each snapshot date, construct an example if there's history
        for snap_date in snapshot_dates:
            # Skip if donor had no transactions before the snapshot date
            if df_acc[date_col].min() > snap_date:
                continue

            # History up to snapshot date (inclusive)
            hist = df_acc[df_acc[date_col] <= snap_date]
            if hist.empty:
                continue

            # PAST ONLY
            first_date = hist[date_col].min()
            last_date = hist[date_col].max()
            tenure_days = (snap_date - first_date).days
            recency_days = (snap_date - last_date).days

            # Only keep donors that donated within the last `active_recency_max` days
            if recency_days > active_recency_max:
                continue

            n_txn = len(hist)
            sum_amt = hist[amt_col].sum()
            avg_amt = sum_amt / n_txn if n_txn > 0 else 0.0
            std_amt = hist[amt_col].std(ddof=0) if n_txn > 1 else 0.0

            # Look into the FUTURE window for labeling
            future_start = snap_date
            future_end = snap_date + pd.Timedelta(days=prediction_window_days)
            future = df_acc[(df_acc[date_col] > future_start) & (df_acc[date_col] <= future_end)]

            churn_label = 1 if future.empty else 0

            rows.append({
                "Account Number": account_id,
                "snapshot_date": snap_date,
                "first_tx_date": first_date,
                "last_tx_date": last_date,
                "tenure_days": tenure_days,
                "recency_days": recency_days,
                "n_txn_past": n_txn,
                "sum_amt_past": sum_amt,
                "avg_amt_past": avg_amt,
                "std_amt_past": std_amt,
                "churn_label": churn_label,
            })

    churn_df = pd.DataFrame(rows)
    if churn_df.empty:
        raise ValueError("No snapshot rows were created. Try relaxing min_history_days or active_recency_max.")

    # ---- Attach demographic features from retention ----
    # To avoid leakage, we DO NOT merge in lifetime revenue / year-to-date, etc.
    # We only bring in relatively static columns like state, ZIP, gender, employer.
    keep_cols = [
        "Account Number",
        "Primary State",
        "Primary ZIP Code",
        "Gender",
        "Employer",
        "Groups",
    ]
    ret_small = retention_df[[c for c in keep_cols if c in retention_df.columns]].copy()

    churn_merged = churn_df.merge(ret_small, on="Account Number", how="left")

    return churn_merged


def train_gradient_boosting_model(churn_df):
    """
    Train a Gradient Boosted Decision Tree on the leakage-free snapshot churn dataset.
    Returns: model, feature_columns (list of column names used as X).
    """
    df = churn_df.copy()
    df = df[df["churn_label"].notna()].copy()

    numeric_features = [
        "tenure_days",
        "recency_days",
        "n_txn_past",
        "sum_amt_past",
        "avg_amt_past",
        "std_amt_past",
    ]
    numeric_features = [f for f in numeric_features if f in df.columns]

    categorical_features = [
        "Primary State",
        "Gender",
        "Employer",
        "Groups",
    ]
    categorical_features = [c for c in categorical_features if c in df.columns]

    # One-hot encode categoricals
    if categorical_features:
        df_cats = pd.get_dummies(df[categorical_features], dummy_na=True)
    else:
        df_cats = pd.DataFrame(index=df.index)

    X_num = df[numeric_features].fillna(0.0)
    X = pd.concat([X_num, df_cats], axis=1)
    y = df["churn_label"].astype(int)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.25, random_state=42, stratify=y
    )

    gb = GradientBoostingClassifier(
        n_estimators=200,
        learning_rate=0.05,
        max_depth=3,
        subsample=0.8,
        random_state=42,
    )

    gb.fit(X_train, y_train)

    y_pred = gb.predict(X_test)
    y_proba = gb.predict_proba(X_test)[:, 1]

    print("Classification report:")
    print(classification_report(y_test, y_pred))

    try:
        auc = roc_auc_score(y_test, y_proba)
        print(f"ROC-AUC: {auc:.3f}")
    except ValueError:
        print("ROC-AUC could not be computed (single class in y_test).")

    importances = pd.Series(gb.feature_importances_, index=X.columns).sort_values(ascending=False)
    print("\nTop 15 feature importances:")
    print(importances.head(15))

    feature_columns = X.columns.tolist()
    return gb, feature_columns

def train_and_save_model(
    model_path: str = "gb_model.pkl",
    features_path: str = "gb_features.pkl",
):
    """
    Builds the snapshot churn dataset from three CSVs,
    trains the gradient boosted model, and saves the model + feature list to disk.
    """
    monthly_clean, retention_clean, transactions_clean = load_and_clean_all(
        "MonthlyDonorsData.csv",
        "RetentionData.csv",
        "TransactionsToPresentData.csv",
    )

    churn_snapshots = build_snapshot_churn_dataset(
        monthly_clean,
        retention_clean,
        transactions_clean,
        prediction_window_days=90,  # predicting 3 months ahead
        snapshot_freq="30D",        # snapshot every ~30 days
        min_history_days=90,
        active_recency_max=90,
    )

    print("Snapshot churn dataset shape:", churn_snapshots.shape)

    model, feature_columns = train_gradient_boosting_model(churn_snapshots)

    joblib.dump(model, model_path)
    joblib.dump(feature_columns, features_path)

    print("Number of unique donors in churn dataset:")
    print(churn_snapshots["Account Number"].nunique())
    print(f"Saved model to {model_path}")
    print(f"Saved feature columns to {features_path}")


def interactive_predict_from_csv(
    model_path: str = "gb_model.pkl",
    features_path: str = "gb_features.pkl",
):
    """
    Terminal-interactive method:
      - Loads a pre-trained model + feature list.
      - Asks user for a CSV file path.
      - Assumes that CSV has the same raw columns used to build features.
      - Outputs churn probabilities for each row.
    """
    if not os.path.exists(model_path) or not os.path.exists(features_path):
        print("Model or feature file not found. Please train and save the model first.")
        return

    model = joblib.load(model_path)
    feature_columns = joblib.load(features_path)

    csv_path = input("Enter path to CSV file with donor features: ").strip()
    if not os.path.exists(csv_path):
        print(f"File not found: {csv_path}")
        return

    df = pd.read_csv(csv_path)
    print(f"Loaded {df.shape[0]} rows from {csv_path}")

    numeric_features = [
        "tenure_days",
        "recency_days",
        "n_txn_past",
        "sum_amt_past",
        "avg_amt_past",
        "std_amt_past",
    ]
    numeric_features = [f for f in numeric_features if f in df.columns]

    categorical_features = [
        "Primary State",
        "Gender",
        "Employer",
        "Groups",
    ]
    categorical_features = [c for c in categorical_features if c in df.columns]

    # One-hot encode categoricals
    if categorical_features:
        df_cats = pd.get_dummies(df[categorical_features], dummy_na=True)
    else:
        df_cats = pd.DataFrame(index=df.index)

    X_num = df[numeric_features].fillna(0.0)
    X = pd.concat([X_num, df_cats], axis=1)

    X = X.reindex(columns=feature_columns, fill_value=0.0)

    # Predict churn probabilities
    churn_proba = model.predict_proba(X)[:, 1]  # probability of churn (class 1)
    df["churn_probability"] = churn_proba

    print("\nSample predictions:")
    cols_to_show = []
    for c in ["Account Number", "snapshot_date", "tenure_days", "recency_days"]:
        if c in df.columns:
            cols_to_show.append(c)
    cols_to_show.append("churn_probability")

    print(df[cols_to_show].head(10))

    save_choice = input("\nSave predictions to a new CSV? (y/n): ").strip().lower()
    if save_choice == "y":
        out_path = input("Enter output CSV path (e.g., predictions.csv): ").strip()
        df.to_csv(out_path, index=False)
        print(f"Saved predictions to {out_path}")
    else:
        print("Predictions not saved to file.")


if __name__ == "__main__":
    print("=== Donor Churn Model ===")
    print("1) Train model and save to disk")
    print("2) Predict churn from a CSV file")
    choice = input("Select an option (1 or 2): ").strip()

    if choice == "1":
        train_and_save_model()
    elif choice == "2":
        interactive_predict_from_csv()
    else:
        print("Invalid choice.")
