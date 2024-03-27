// Fetch the latest release version from GitHub
const { Octokit } = require("@octokit/rest");
const owner = 'redpanda-data';
const repo = 'redpanda';

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
    // Fetch the latest release
    const release = await github.rest.repos.getLatestRelease({ owner, repo });
    const tag = release.data.tag_name;
    latestRedpandaReleaseVersion = tag.replace('v', '');

    // Get reference of the tag
    const tagRef = await github.rest.git.getRef({ owner, repo, ref: `tags/${tag}` });
    const releaseSha = tagRef.data.object.sha;

    // Get the tag object to extract the commit hash
    const tagData = await github.rest.git.getTag({ owner, repo, tag_sha: releaseSha });
    latestRedpandaReleaseCommitHash = tagData.data.object.sha.substring(0, 7);

    console.log(latestRedpandaReleaseVersion);
  } catch (error) {
    console.error(error);
    process.exit(1)
  }
})()