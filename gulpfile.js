'use strict'

const connect = require('gulp-connect')
const fs = require('fs')
const generator = require('@antora/site-generator')
const { reload: livereload } = process.env.LIVERELOAD === 'true' ? require('gulp-connect') : {}
const { series, src, watch } = require('gulp')
const yaml = require('js-yaml')

const playbookFilename = 'local-antora-playbook.yml'
const playbook = yaml.load(fs.readFileSync(playbookFilename, 'utf8'))
const outputDir = (playbook.output || {}).dir || './build/site'
const serverConfig = { name: 'Preview Site', livereload, port: 5002, root: outputDir }
const antoraArgs = ['--playbook', playbookFilename, '--clean', true]
const watchPatterns = playbook.content.sources.filter((source) => !source.url.includes(':')).reduce((accum, source) => {
  if (source.start_paths) {
    let startPathsArray = Array.isArray(source.start_paths) ? source.start_paths : source.start_paths.split(',').map(path => path.trim());
    startPathsArray.forEach(start_path => {
      accum.push(`${source.url}/${start_path ? start_path + '/' : ''}antora.yml`)
      accum.push(`${source.url}/${start_path ? start_path + '/' : ''}**/*.adoc`)
    });
  } else {
    accum.push(`${source.url}/${source.start_path ? source.start_path + '/' : ''}antora.yml`)
    accum.push(`${source.url}/${source.start_path ? source.start_path + '/' : ''}**/*.adoc`)
  }
  return accum
}, [])

function generate (done) {
  generator(antoraArgs, process.env)
    .then(() => {
      if (livereload) connect.reload();
      done();
    })
    .catch((err) => {
      console.log(err)
      done()
    })
}

let isFirstRun = true;

async function serve (done) {
  connect.server(serverConfig, function () {
    this.server.on('close', done)
    watch(watchPatterns, generate)
    if (livereload) watch(this.root).on('change', (filepath) => src(filepath, { read: false }).pipe(livereload()))
    if (isFirstRun) {
      import('open').then(open => {
        open.default(`http://localhost:${serverConfig.port}/`)
      })
      isFirstRun = false;
    }
  })
}

module.exports = { serve, generate, default: series(generate, serve) }
