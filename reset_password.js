const { Client } = require('pg');
const bcrypt = require('bcrypt');

// Database connection configuration
const client = new Client({
  user: 'Anthony',
  host: 'localhost',
  database: 'familynest',
  password: '', // Add your database password if needed
  port: 5432,
});

async function resetPassword() {
  try {
    // Connect to the database
    await client.connect();
    console.log('Connected to PostgreSQL database');

    // Generate bcrypt hash for 'user2123'
    const saltRounds = 10;
    const plainPassword = 'user2123';
    const passwordHash = await bcrypt.hash(plainPassword, saltRounds);
    
    console.log(`Generated password hash for "${plainPassword}"`);
    
    // Update the user's password
    const query = 'UPDATE users SET password = $1 WHERE username = $2';
    const values = [passwordHash, 'user2'];
    
    const res = await client.query(query, values);
    console.log(`Password updated for user2. ${res.rowCount} row(s) affected.`);
  } catch (err) {
    console.error('Error resetting password:', err);
  } finally {
    // Close the database connection
    await client.end();
    console.log('Database connection closed');
  }
}

resetPassword(); 