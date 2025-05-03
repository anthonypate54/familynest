#!/bin/bash

# Reset password script for user2 in familynest database
# This script attempts multiple password hashing methods to ensure compatibility

# Configuration
DB_USER="Anthony"
DB_NAME="familynest"
TARGET_USER="user2"
NEW_PASSWORD="user2123"

echo "=== FamilyNest Password Reset Tool ==="
echo "Attempting to reset password for $TARGET_USER to $NEW_PASSWORD"
echo

# Check if PostgreSQL is available
if ! command -v psql &> /dev/null; then
    echo "Error: PostgreSQL command-line tool (psql) not found."
    echo "Please make sure PostgreSQL is installed and in your PATH."
    exit 1
fi

# Test database connection
echo "Testing database connection..."
if ! psql -U $DB_USER -d $DB_NAME -c "SELECT 1" &> /dev/null; then
    echo "Error: Cannot connect to database. Please check your credentials."
    echo "Command used: psql -U $DB_USER -d $DB_NAME"
    exit 1
fi
echo "Database connection successful!"
echo

# Check if user exists
echo "Checking if user exists..."
USER_EXISTS=$(psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM app_user WHERE username = '$TARGET_USER';")
USER_EXISTS=$(echo $USER_EXISTS | xargs) # Trim whitespace

if [ "$USER_EXISTS" -eq "0" ]; then
    echo "Error: User '$TARGET_USER' not found in the database."
    echo "Available users:"
    psql -U $DB_USER -d $DB_NAME -c "SELECT username FROM app_user LIMIT 10;"
    exit 1
fi
echo "User '$TARGET_USER' found in database!"
echo

# Check current password format to determine hashing method
echo "Checking current password format..."
CURRENT_HASH=$(psql -U $DB_USER -d $DB_NAME -t -c "SELECT password FROM app_user WHERE username = '$TARGET_USER';")
CURRENT_HASH=$(echo $CURRENT_HASH | xargs) # Trim whitespace

echo "Current password hash: ${CURRENT_HASH:0:10}... (truncated for security)"

# Function to attempt password reset with specific method
attempt_reset() {
    local method=$1
    local query=$2
    
    echo
    echo "Attempting password reset using $method method..."
    RESULT=$(psql -U $DB_USER -d $DB_NAME -c "$query" 2>&1)
    
    if [[ $RESULT == *"UPDATE 1"* ]]; then
        echo "Success! Password reset using $method method."
        return 0
    else
        echo "Method failed. Error: $RESULT"
        return 1
    fi
}

# Try creating pgcrypto extension if it doesn't exist
echo "Enabling pgcrypto extension..."
psql -U $DB_USER -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" &> /dev/null

# Attempt various methods based on what we discovered
SUCCESS=false

# Method 1: bcrypt (most secure)
if ! $SUCCESS; then
    BCRYPT_QUERY="UPDATE app_user SET password = crypt('$NEW_PASSWORD', gen_salt('bf', 10)) WHERE username = '$TARGET_USER';"
    if attempt_reset "bcrypt" "$BCRYPT_QUERY"; then
        SUCCESS=true
    fi
fi

# Method 2: SHA-256
if ! $SUCCESS; then
    SHA256_QUERY="UPDATE app_user SET password = encode(digest('$NEW_PASSWORD', 'sha256'), 'hex') WHERE username = '$TARGET_USER';"
    if attempt_reset "SHA-256" "$SHA256_QUERY"; then
        SUCCESS=true
    fi
fi

# Method 3: MD5
if ! $SUCCESS; then
    MD5_QUERY="UPDATE app_user SET password = md5('$NEW_PASSWORD') WHERE username = '$TARGET_USER';"
    if attempt_reset "MD5" "$MD5_QUERY"; then
        SUCCESS=true
    fi
fi

# Method 4: Plain text (last resort)
if ! $SUCCESS; then
    PLAIN_QUERY="UPDATE app_user SET password = '$NEW_PASSWORD' WHERE username = '$TARGET_USER';"
    if attempt_reset "plain text" "$PLAIN_QUERY"; then
        echo "WARNING: Password stored as plain text. This is insecure!"
        SUCCESS=true
    fi
fi

# Summary
echo
if $SUCCESS; then
    echo "=== Password Reset Summary ==="
    echo "Username: $TARGET_USER"
    echo "New password: $NEW_PASSWORD"
    echo "Database: $DB_NAME"
    echo
    echo "Log in with these credentials in your FamilyNest application."
else
    echo "All password reset methods failed."
    echo "Please check your database schema and authentication system."
    echo "You may need to manually reset the password."
fi 