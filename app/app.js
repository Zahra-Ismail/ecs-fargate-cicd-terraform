const express = require('express');
const app = express();

// Application port
const PORT = 8080;

// Homepage route
app.get('/', (req, res) => {
  res.send('Hello! My name is Fathi. ECS Fargate CI/CD Assignment is running successfully.');
});

// Health check route
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'OK' });
});

// Start server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
