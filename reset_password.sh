#!/bin/bash

# Configuration
DB_USER="Anthony"
DB_NAME="familynest"
TARGET_USER="user2"
NEW_PASSWORD="user2123"

# Generate bcrypt hash (requires pgcrypto extension)
HASH_QUERY="SELECT encode(digest('$NEW_PASSWORD', 'sha256'), 'hex');"
BCRYPT_QUERY="SELECT crypt('$NEW_PASSWORD', gen_salt('bf', 10));"

echo "Attempting to reset password for $TARGET_USER..."

# Try method 1: SHA-256 hash
echo "Trying SHA-256 hash method..."
SHA256_HASH=$(psql -U $DB_USER -d $DB_NAME -t -c "$HASH_QUERY")
SHA256_HASH=$(echo $SHA256_HASH | xargs) # Trim whitespace
psql -U $DB_USER -d $DB_NAME -c "UPDATE users SET password = '$SHA256_HASH' WHERE username = '$TARGET_USER';"

# Try method 2: bcrypt (if method 1 fails)
echo "Trying bcrypt method (requires pgcrypto extension)..."
psql -U $DB_USER -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
psql -U $DB_USER -d $DB_NAME -c "UPDATE users SET password = crypt('$NEW_PASSWORD', gen_salt('bf', 10)) WHERE username = '$TARGET_USER';"

# Check for successful update
AFFECTED=$(psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM users WHERE username = '$TARGET_USER';")
AFFECTED=$(echo $AFFECTED | xargs) # Trim whitespace

if [ "$AFFECTED" -eq "1" ]; then
  echo "Password successfully reset for $TARGET_USER"
  echo "New password is: $NEW_PASSWORD"
else
  echo "Failed to find user: $TARGET_USER"
fi 