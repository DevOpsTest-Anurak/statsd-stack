require('dotenv').config();
const lynx = require('lynx');

// Instantiate a metrics client
// Note: the metric hostname is hardcoded here
const metrics = new lynx(process.env.METRICSHOST, process.env.METRICSPORT);

// Sleep for a given number of milliseconds
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

let runLoop = true;

async function main() {
  const delay = Math.random() * 1000;
  // Send message to the metrics server
  metrics.timing('test.core.delay',delay);

  // Sleep for a random number of milliseconds to avoid flooding metrics server
  return sleep(3000);
}

// Handle signals to gracefully exit the loop
process.on('SIGINT', () => {
  console.log('Received SIGINT. Exiting gracefully...');
  runLoop = false;
});

// Infinite loop with exit condition
(async () => {
  console.log("🚀🚀🚀");
  while (runLoop) {
    await main();
  }
})()
  .then(console.log)
  .catch(console.error);
