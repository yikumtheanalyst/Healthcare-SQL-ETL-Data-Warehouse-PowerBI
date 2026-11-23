"""Configuration-driven SQL Server DW to RFC-style CSV exporter.

Run: python export_dw_tables.py
Configuration: environment variables SQL_SERVER, SQL_DATABASE, SQL_EXPORT_DIR,
SQL_ODBC_DRIVER (optional), SQL_EXPORT_SCHEMA (optional).
Uses Windows integrated authentication as the executing Windows account.
"""

import csv
import os
import re
import sys
from pathlib import Path

import pyodbc

SERVER = os.getenv('SQL_SERVER', r'.\YIKUMSQLSERVER')
DATABASE = os.getenv('SQL_DATABASE', 'ETL_DB')
SCHEMA = os.getenv('SQL_EXPORT_SCHEMA', 'dw')
EXPORT_DIR = Path(os.getenv('SQL_EXPORT_DIR', r'C:\Projects\SQL_ETL\Healthcare-SQL-ETL-Data-Warehouse\data\etl clean'))
DRIVER = os.getenv('SQL_ODBC_DRIVER', 'ODBC Driver 17 for SQL Server')
BATCH_SIZE = 10000
SAFE_IDENTIFIER = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def quote_identifier(identifier):
    if not SAFE_IDENTIFIER.fullmatch(identifier):
        raise ValueError(f'Unsafe SQL identifier: {identifier!r}')
    return '[' + identifier + ']'


def connect():
    return pyodbc.connect(
        f'DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};'
        'Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;',
        autocommit=True,
        timeout=30,
    )


def main():
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    schema_sql = quote_identifier(SCHEMA)
    total_tables = 0
    with connect() as conn:
        cfg = conn.cursor()
        cfg.execute(f'SELECT table_name FROM {schema_sql}.[ETL_Config_FileList] '
                    'WHERE is_active = 1 ORDER BY load_order, table_name')
        table_names = [str(row[0]) for row in cfg.fetchall()]
        if not table_names:
            raise RuntimeError('No active tables in ETL_Config_FileList')

        for table_name in table_names:
            table_sql = quote_identifier(table_name)
            full_name = f'{schema_sql}.{table_sql}'
            cursor = conn.cursor()
            cursor.execute(f'SELECT * FROM {full_name}')
            headers = [column[0] for column in cursor.description]
            if not headers:
                raise RuntimeError(f'No columns found for {full_name}')

            destination = EXPORT_DIR / f'{table_name}.csv'
            temporary = EXPORT_DIR / f'{table_name}.csv.tmp'
            rows_written = 0
            print(f'Exporting {full_name} -> {destination}', flush=True)
            try:
                with temporary.open('w', encoding='utf-8-sig', newline='') as file:
                    writer = csv.writer(file, dialect='excel', quoting=csv.QUOTE_ALL)
                    writer.writerow(headers)
                    while True:
                        batch = cursor.fetchmany(BATCH_SIZE)
                        if not batch:
                            break
                        writer.writerows(batch)
                        rows_written += len(batch)
                cursor.close()
                # This count assumes the source tables are not being modified during export.
                check = conn.cursor()
                check.execute(f'SELECT COUNT_BIG(*) FROM {full_name}')
                expected_rows = int(check.fetchone()[0])
                check.close()
                if rows_written != expected_rows:
                    raise RuntimeError(
                        f'Row count mismatch for {table_name}: exported {rows_written:,}, '
                        f'current SQL count {expected_rows:,}'
                    )
                temporary.replace(destination)
                total_tables += 1
                print(f'OK: {table_name} ({rows_written:,} rows)', flush=True)
            except Exception:
                try:
                    cursor.close()
                except Exception:
                    pass
                temporary.unlink(missing_ok=True)
                raise

    print(f'Completed: {total_tables} tables exported.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(f'EXPORT FAILED: {exc}', file=sys.stderr, flush=True)
        sys.exit(1)
