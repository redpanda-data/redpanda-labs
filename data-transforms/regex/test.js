const fs = require('fs');
const path = require('path');
const { runTests } = require("doc-detective-core");

const configPath = path.join(process.cwd(), 'doc-tests/test-config.json');
const outputPath = path.join(process.cwd(), 'doc-tests/test_output.json');

try {
  // Read the configuration file
  const rawData = fs.readFileSync(configPath);
  const config = JSON.parse(rawData);

  runTests(config)
    .then((report) => {
      const failedSteps = report.specs.flatMap((spec) =>
        spec.tests.flatMap((test) =>
          test.contexts
            .filter(context => context.result === "FAIL")
            .map(context => ({
              ...context,
              file: spec.file, // Include file info for each context
              steps: context.steps.map(step => ({
                ...step,
                ...(step.action === 'typeKeys' && { keys: ['***'] }) // Mask keys if action is typeKeys
              }))
            }))
        )
      );

      if (failedSteps.length > 0) {
        fs.writeFileSync(outputPath, JSON.stringify(failedSteps, null, 2));
        console.log('Failed tests have been written to test_output.json');
        console.log(JSON.stringify(failedSteps, null, 2))
        process.exit(1)
      } else {
        console.log('All tests passed.');
      }
    })
    .catch((error) => {
      console.error('Error running tests:', error);
      fs.writeFileSync(outputPath, `Error running tests: ${error}`);
      process.exit(1)
    });
} catch (error) {
  console.error('Failed to read config or run tests:', error);
  fs.writeFileSync(outputPath, `Failed to read config or run tests: ${error}`);
  process.exit(1)
}