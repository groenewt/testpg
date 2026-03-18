#!/usr/bin/env bash
###@TODO:CLEAN this shit lol (originally for pgai!)


PG_BIN="/usr/lib/postgresql/17/bin"
if [ ! -d "$PG_BIN" ]; then
    echo "Error: PostgreSQL binaries not found at $PG_BIN"
    exit 1
fi

# PostgreSQL data directory
export PGDATA=${PGDATA:-/var/lib/postgresql/data}
export POSTGRES_USER=${POSTGRES_USER:-postgres}
export POSTGRES_DB=${POSTGRES_DB:-postgres}
echo "[DEBUG]:PG password is ${POSTGRES_PASSWORD}"

# Check password configuration
[[ -n "$POSTGRES_PASSWORD" ] && \
	echo "✓ POSTGRES_PASSWORD is configured" || echo "⚠ WARNING: POSTGRES_PASSWORD is not set - database will have no password!"
#:/ yeah

# Ensure directory exists with correct permissions
if [ ! -d "$PGDATA" ]; then
    mkdir -p "$PGDATA"
fi
chown -R postgres:postgres "$PGDATA"
chown -R postgres:postgres /etc/postgresql
# Initialize database if needed
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "=== Starting PostgreSQL initialization ==="

    # Run initdb as postgres user
    echo "Running initdb..."
    su - postgres -c "${PG_BIN}/initdb -D '${PGDATA}' --encoding=UTF8 --locale=en_US.UTF-8"

    # Copy configuration files
    echo "Copying configuration files..."
    cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
    cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
    chown postgres:postgres "$PGDATA/postgresql.conf" "$PGDATA/pg_hba.conf"

    # Start PostgreSQL temporarily to set password
    echo "Starting PostgreSQL temporarily for setup..."
    su - postgres -c "${PG_BIN}/pg_ctl -D '${PGDATA}' -o '-p 5432' -w start"

    # Wait for postgres to be ready
    sleep 2

    # Set postgres password if provided
    if [ -n "$POSTGRES_PASSWORD" ]; then
        echo "Setting postgres user password with scram-sha-256..."
        su - postgres -c "PGPORT=5432 ${PG_BIN}/psql -U postgres -c \"SET password_encryption = 'scram-sha-256'; ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';\""
        echo "Password set successfully"
    fi

    # Create custom database if specified
    if [ "$POSTGRES_DB" != "postgres" ]; then
        echo "Creating database: $POSTGRES_DB"
        su - postgres -c "PGPORT=5432 ${PG_BIN}/createdb -U postgres -O ${POSTGRES_USER} '${POSTGRES_DB}'" || echo "Database may already exist"
    fi

    # Create extensions
    echo "Creating extensions..."
    su - postgres -c "PGPORT=5432 ${PG_BIN}/psql -U postgres -d ${POSTGRES_DB} -c 'CREATE EXTENSION IF NOT EXISTS postgis;'" || echo "PostGIS extension failed"
    su - postgres -c "PGPORT=5432 ${PG_BIN}/psql -U postgres -d ${POSTGRES_DB} -c 'CREATE EXTENSION IF NOT EXISTS vector;'" || echo "Vector extension failed"
    su - postgres -c "PGPORT=5432 ${PG_BIN}/psql -U postgres -d ${POSTGRES_DB} -c 'CREATE EXTENSION IF NOT EXISTS age;' -c 'SET search_path TO ag_catalog;'" || echo "AGE extension failed"
    su - postgres -c "PGPORT=5432 ${PG_BIN}/psql -U postgres -d ${POSTGRES_DB} -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;'" || echo "pg_stat_statements extension failed"
    su - postgres -c "PGPORT=5432 ${PG_BIN}/psql -U postgres -d ${POSTGRES_DB} -c 'CREATE EXTENSION IF NOT EXISTS plpython3u;'" || echo "plpython3u extension failed"

    # Verify Python environment for PL/Python
    echo "Verifying Python environment..."
    su - postgres -c "PGPORT=5432 ${PG_BIN}/psql -U postgres -d ${POSTGRES_DB} -c \"
    DO \\$\\$
    import sys
    plpy.notice('Python version: ' + sys.version)
    try:
        import numpy
        plpy.notice('NumPy imported successfully from: ' + numpy.__file__)
    except ImportError as e:
        plpy.error('NumPy import failed: ' + str(e))
    \\$\\$ LANGUAGE plpython3u;\"" || echo "Python verification failed"

    echo "Extensions created"

    # Stop temporary PostgreSQL
    echo "Stopping temporary PostgreSQL..."
    su - postgres -c "${PG_BIN}/pg_ctl -D '${PGDATA}' -w stop"

    echo "=== Database initialization completed ==="
fi

# Start PostgreSQL with any additional arguments from docker-compose
echo "Starting PostgreSQL..."
if [ "$#" -eq 0 ]; then
    # No additional arguments
    exec su - postgres -c "${PG_BIN}/postgres -D '${PGDATA}'"
else
    # Pass arguments from docker-compose command
    POSTGRES_ARGS=""
    for arg in "$@"; do
        if [ "$arg" != "postgres" ]; then
            POSTGRES_ARGS="$POSTGRES_ARGS $arg"
        fi
    done
    exec su - postgres -c "${PG_BIN}/postgres -D '${PGDATA}' $POSTGRES_ARGS"
fi
