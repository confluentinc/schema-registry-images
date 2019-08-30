#!/usr/bin/env groovy

dockerfile {
    dockerPush = true
    dockerRepos = ['confluentinc/schema-registry',]
    mvnPhase = 'package'
    mvnSkipDeploy = true
    nodeLabel = 'docker-oraclejdk8-compose'
    slackChannel = 'tools' //TODO: change to correct team
    upstreamProjects = ['confluentinc/common']
    dockerPullDeps = ['confluentinc/cp-base-new']
    usePackages = true
}
