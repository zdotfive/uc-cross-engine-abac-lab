"""Run a .sql file statement by statement on the SQL warehouse and log the results.

Usage: python scripts/run_sql.py <file.sql> [--as-reader] [--max-rows N]

Admin runs use a Databricks CLI profile (PROFILE, default FREE). --as-reader uses the
reader service principal from .env. ${READER_APP_ID} in the SQL is replaced with
DATABRICKS_CLIENT_ID and ${CATALOG} with $CATALOG (default labs).
Credentials are never printed.
"""
import os, re, sys, time
from dotenv import dotenv_values
from databricks.sdk import WorkspaceClient
from databricks.sdk.service.sql import StatementState

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
env = dotenv_values(os.path.join(ROOT, ".env"))
args = sys.argv[1:]
path = args.pop(0)
as_reader = "--as-reader" in args
max_rows = int(args[args.index("--max-rows") + 1]) if "--max-rows" in args else 20

if as_reader:
    w = WorkspaceClient(host=env["DATABRICKS_HOST"], client_id=env["DATABRICKS_CLIENT_ID"],
                        client_secret=env["DATABRICKS_CLIENT_SECRET"], auth_type="oauth-m2m")
else:
    w = WorkspaceClient(profile=os.environ.get("PROFILE", "FREE"))

sql = (open(path).read().replace("${READER_APP_ID}", env.get("DATABRICKS_CLIENT_ID", ""))
       .replace("${CATALOG}", os.environ.get("CATALOG", "labs")))
sql = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))
stmts = [s.strip() for s in sql.split(";") if s.strip()]
print(f"# {os.path.basename(path)} as {'reader' if as_reader else 'admin'}, {len(stmts)} statements")

failed = 0
for s in stmts:
    head = re.sub(r"\s+", " ", s)[:120]
    t0 = time.time()
    r = w.statement_execution.execute_statement(statement=s, warehouse_id=env["DATABRICKS_WAREHOUSE_ID"],
                                                wait_timeout="50s")
    while r.status.state in (StatementState.PENDING, StatementState.RUNNING):
        time.sleep(1)
        r = w.statement_execution.get_statement(r.statement_id)
    dt = time.time() - t0
    print(f"\n> {head}\n  state={r.status.state.value} ({dt:.3f}s)")
    if r.status.error:
        failed += 1
        print(f"  error: {r.status.error.error_code}: {r.status.error.message}")
    elif r.result and r.result.data_array is not None and r.manifest:
        print("  " + " | ".join(c.name for c in r.manifest.schema.columns))
        for row in r.result.data_array[:max_rows]:
            print("  " + " | ".join("NULL" if v is None else str(v) for v in row))
print(f"\n# done, {failed} failed")
