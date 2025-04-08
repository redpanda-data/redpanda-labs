const { Octokit } = require("@octokit/rest");
const semver = require("semver");
const owner = 'redpanda-data';
const repo = 'console';

let githubOptions = {
  userAgent: 'Redpanda Docs',
  baseUrl: 'https://api.github.com',
};

if (process.env.REDPANDA_GITHUB_TOKEN) {
  githubOptions.auth = process.env.REDPANDA_GITHUB_TOKEN;
}

const github = new Octokit(githubOptions);

(async () => {
  try {
    // Fetch the latest 10 releases
    const releases = await github.rest.repos.listReleases({
      owner,
      repo,
      per_page: 10,
    });

    // Filter valid semver tags and sort them
    const sortedReleases = releases.data
      .map(release => release.tag_name)
      .filter(tag => semver.valid(tag))
      // Sort in descending order to get the highest version first
      .sort(semver.rcompare);

    if (sortedReleases.length > 0) {
      console.log(sortedReleases[0]);
    } else {
      console.log("No valid semver releases found.");
      process.exit(1)
    }
  } catch (error) {
    console.error(error);
    process.exit(1)
  }
})()