const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

console.log('🚀 Starting Just Speed It Production Environment...');

// Check if API dependencies are installed
const apiNodeModulesPath = path.join(__dirname, 'api', 'node_modules');
if (!fs.existsSync(apiNodeModulesPath)) {
  console.log('📦 Installing API dependencies (first time only)...');
  try {
    execSync('npm install --production', {
      cwd: path.join(__dirname, 'api'),
      stdio: 'inherit'
    });
    console.log('✅ API dependencies installed!');
  } catch (error) {
    console.error('❌ Failed to install API dependencies:', error);
    process.exit(1);
  }
}

// Start API server in production mode
console.log('📡 Starting API server on port', process.env.API_PORT || 3001, '...');
const apiProcess = spawn('node', ['dist/index.js'], {
  cwd: path.join(__dirname, 'api'),
  stdio: 'inherit',
  shell: true,
  env: {
    ...process.env,
    NODE_ENV: 'production',
    PORT: process.env.API_PORT || 3001
  }
});

// Wait a moment for API to start
setTimeout(() => {
  console.log('🌐 Starting Frontend server on port', process.env.PORT || 3000, '...');
  const frontendProcess = spawn('npm', ['run', 'start'], {
    cwd: path.join(__dirname, 'frontend'),
    stdio: 'inherit',
    shell: true,
    env: {
      ...process.env,
      NODE_ENV: 'production',
      PORT: process.env.PORT || 3000,
      NEXT_PUBLIC_API_URL: `http://localhost:${process.env.API_PORT || 3001}`
    }
  });

  // Handle process termination
  process.on('SIGINT', () => {
    console.log('\n🛑 Stopping servers...');
    apiProcess.kill();
    frontendProcess.kill();
    process.exit(0);
  });

  // Handle API process exit
  apiProcess.on('exit', (code) => {
    console.error(`❌ API process exited with code ${code}`);
    frontendProcess.kill();
    process.exit(code);
  });

  // Handle Frontend process exit
  frontendProcess.on('exit', (code) => {
    console.error(`❌ Frontend process exited with code ${code}`);
    apiProcess.kill();
    process.exit(code);
  });

}, 2000);

console.log('✅ Servers starting...');
console.log('Frontend: http://localhost:' + (process.env.PORT || 3000));
console.log('API: http://localhost:' + (process.env.API_PORT || 3001));

