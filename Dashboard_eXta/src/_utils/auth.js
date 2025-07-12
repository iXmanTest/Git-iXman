const jwt = require('jsonwebtoken');

const SECRET_KEY = process.env.JWT_SECRET;

// Generate JWT Token
function generateToken(user) {
  return jwt.sign({ userId: user.id, username: user.username }, SECRET_KEY, { expiresIn: '1h' });
}

// Verify JWT Token
function verifyToken(token) {
  try {
    return jwt.verify(token, SECRET_KEY);
  } catch (error) {
    return null;
  }
}

module.exports = { generateToken, verifyToken };