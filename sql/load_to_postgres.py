"""Load the cleaned IPL CSVs into a PostgreSQL database called 'ipl'.
Run from the project root:  python sql/load_to_postgres.py
"""
import getpass
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

CLEAN = Path(__file__).resolve().parent.parent / "data" / "cleaned"

password = getpass.getpass("PostgreSQL password for user 'postgres': ")
engine = create_engine(URL.create(
    "postgresql+psycopg2", username="postgres", password=password,
    host="localhost", port=5432, database="ipl"))

tables = {
    "teams": "teams.csv",
    "players": "players.csv",
    "matches": "matches_clean.csv",
    "deliveries": "deliveries_clean.csv",
}

for name, file in tables.items():
    df = pd.read_csv(CLEAN / file)
    if name == "matches":
        df["date"] = pd.to_datetime(df["date"])
    if name == "deliveries":
        df = df.rename(columns={"over": "over_no"})  # 'over' is an SQL keyword
    df.to_sql(name, engine, if_exists="replace", index=False, chunksize=2000, method="multi")
    print(f"Loaded {name}: {len(df):,} rows")

with engine.begin() as conn:
    for stmt in [
        "ALTER TABLE teams ADD PRIMARY KEY (team_id)",
        "ALTER TABLE players ADD PRIMARY KEY (player_id)",
        "ALTER TABLE matches ADD PRIMARY KEY (id)",
        "CREATE INDEX idx_deliveries_match ON deliveries (match_id)",
        "CREATE INDEX idx_deliveries_batter ON deliveries (batter)",
        "CREATE INDEX idx_deliveries_bowler ON deliveries (bowler)",
    ]:
        conn.execute(text(stmt))
print("Keys and indexes created. Done.")
