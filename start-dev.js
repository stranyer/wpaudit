const { spawn } = require('child_process');
const path = require('path');

console.log('🚀 Starting Just Audit It Development Environment...');

// Start API server
console.log('📡 Starting API server...');
const apiProcess = spawn('npm', ['run', 'dev'], {
  cwd: path.join(__dirname, 'api'),
  stdio: 'inherit',
  shell: true
});

// Wait a moment for API to start
setTimeout(() => {
  console.log('🌐 Starting Frontend server...');
  const frontendProcess = spawn('npm', ['run', 'dev'], {
    cwd: path.join(__dirname, 'frontend'),
    stdio: 'inherit',
    shell: true
  });

  // Handle process termination
  process.on('SIGINT', () => {
    console.log('\n🛑 Stopping servers...');
    apiProcess.kill();
    frontendProcess.kill();
    process.exit(0);
  });

}, 3000);

console.log('✅ Servers starting...');
console.log('Frontend: http://localhost:3000');
console.log('API: http://localhost:3001');
console.log('Press Ctrl+C to stop all servers');
