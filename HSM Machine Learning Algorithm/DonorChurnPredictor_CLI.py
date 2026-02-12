import os
import sys
import pandas as pd
import joblib
import numpy as np

def resource_path(relative_path: str) -> str:
    """
    Get absolute path to resource, works for dev and for PyInstaller onefile.
    """
    base_path = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(sys.argv[0])))
    return os.path.join(base_path, relative_path)

def load_model_and_features(model_path="gb_model.pkl", features_path="gb_features.pkl"):
    model_path = resource_path(model_path)
    features_path = resource_path(features_path)

    if not os.path.exists(model_path):
        print(f"ERROR: Model file not found: {model_path}")
        input("Press Enter to exit...")
        sys.exit(1)
    if not os.path.exists(features_path):
        print(f"ERROR: Feature file not found: {features_path}")
        input("Press Enter to exit...")
        sys.exit(1)

    model = joblib.load(model_path)
    feature_columns = joblib.load(features_path)
    return model, feature_columns

def build_feature_matrix(df, feature_columns):
    """
    Rebuilds the feature matrix X from a CSV that already has:
      - tenure_days, recency_days, n_txn_past, sum_amt_past, avg_amt_past, std_amt_past
      - optional: Primary State, Gender, Employer, Groups
    Exactly the same preprocessing logic as training, but without labels.
    """
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

    # Align to training feature columns
    X = X.reindex(columns=feature_columns, fill_value=0.0)
    return X

def main():
    print("=== Donor Churn Predictor ===")
    print("This tool will read a CSV of donor features and add churn_probability and churn_risk columns.")
    print("The CSV must contain at least these columns:")
    print("  tenure_days, recency_days, n_txn_past, sum_amt_past, avg_amt_past, std_amt_past")
    print("And optionally: Primary State, Gender, Employer, Groups")
    print()

    model, feature_columns = load_model_and_features()

    raw_path = input("Enter the path to the donor CSV file: ")

    csv_path = raw_path.strip().strip('"').strip("'")
    csv_path = csv_path.replace(r"\ ", " ")


    if not os.path.exists(csv_path):
        print(f"ERROR: File not found: {csv_path}")
        input("Press Enter to exit...")
        sys.exit(1)

    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        print(f"ERROR: Could not read CSV: {e}")
        input("Press Enter to exit...")
        sys.exit(1)

    print(f"Loaded {df.shape[0]} rows.")

    # Build feature matrix
    X = build_feature_matrix(df, feature_columns)

    # Predict churn probabilities (class 1 = churn)
    churn_proba = model.predict_proba(X)[:, 1]
    df["churn_probability"] = churn_proba

    # Add a simple label based on a threshold
    threshold = 0.5  # you can change this if you want stricter “likely”
    df["churn_risk"] = np.where(
        df["churn_probability"] >= threshold,
        "Likely",
        "Unlikely"
    )

    # Try to show some identifiers if present
    cols_to_show = []
    for c in ["Account Number", "snapshot_date", "tenure_days", "recency_days"]:
        if c in df.columns:
            cols_to_show.append(c)
    cols_to_show.extend(["churn_probability", "churn_risk"])

    print("\nSample of predictions:")
    print(df[cols_to_show].head(10))

    # Ask where to save
    default_out = "donor_predictions.csv"
    out_path = input(f"\nEnter output CSV file name [{default_out}]: ").strip()
    if out_path == "":
        out_path = default_out

    try:
        df.to_csv(out_path, index=False)
        print(f"\nPredictions saved to: {out_path}")
    except Exception as e:
        print(f"ERROR: Could not save CSV: {e}")
        input("Press Enter to exit...")
        sys.exit(1)

    input("\nDone. Press Enter to exit...")

if __name__ == "__main__":
    main()
