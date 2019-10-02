#!/usr/bin/env groovy

dockerfile {
    dockerPush = false
    dockerRepos = ['confluentinc/cp-schema-registry',]
    mvnPhase = 'package'
    mvnSkipDeploy = true
    nodeLabel = 'docker-oraclejdk8-compose-swarm'
    slackChannel = 'tools-notifications' //TODO: change to correct team
    upstreamProjects = [] //TODO: after roll out, this will be the cp-docker-images-overlay job
    dockerPullDeps = ['confluentinc/cp-base-new']
    usePackages = true
    cron = '' // Disable the cron because this job requires parameters
}
