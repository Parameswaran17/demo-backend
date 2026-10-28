// Declarative Jenkins pipeline that builds and deploys the full app
// (frontend repo + backend repo) by calling deploy/deploy.sh.
//
// No build parameters: everything is configured in this file and the pipeline
// starts automatically when a new commit lands on the backend repo's main branch.
//
// To deploy a specific version instead of the latest, change FRONTEND_REF /
// BACKEND_REF below to a commit SHA, branch or tag, then commit and push.
//
// Prerequisites on the Jenkins agent (Ubuntu):
//   - docker + docker compose plugin; the 'jenkins' user is in the 'docker' group
//   - git, curl
//
pipeline {
    agent any

    environment {
        FRONTEND_REPO = 'https://github.com/Parameswaran17/demo-frontend.git'
        BACKEND_REPO  = 'https://github.com/Parameswaran17/demo-backend.git'
        FRONTEND_REF  = 'main'      // commit SHA / branch / tag, e.g. '7334a96'
        BACKEND_REF   = 'main'      // commit SHA / branch / tag, e.g. '038b197'
        APP_PORT      = '8081'      // Jenkins itself uses 8080
        WORKSPACE_DIR = "${env.JENKINS_HOME}/deploy-workspace"
    }

    options {
        timestamps()
        disableConcurrentBuilds()          // never run two deployments at once
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    triggers {
        // Check the backend repo for new commits every ~2 minutes and build when it changes.
        // (A GitHub webhook would need a public URL; polling works on localhost.)
        pollSCM('H/2 * * * *')
    }

    stages {
        stage('Checkout deploy scripts') {
            steps { checkout scm }
        }

        stage('Lint scripts') {
            steps {
                sh 'bash -n deploy/deploy.sh'
            }
        }

        stage('Build, test & deploy') {
            steps {
                // deploy.sh clones both repos, checks out the requested refs,
                // builds images tagged with the commit SHA, runs backend tests,
                // deploys with docker compose and performs a health check.
                sh '''
                    chmod +x deploy/deploy.sh
                    ./deploy/deploy.sh \
                      -F "$FRONTEND_REPO" -B "$BACKEND_REPO" \
                      -f "$FRONTEND_REF"  -b "$BACKEND_REF" \
                      -w "$WORKSPACE_DIR" -p "$APP_PORT"
                '''
            }
        }

        stage('Smoke test') {
            steps {
                sh '''
                    curl -fsS "http://localhost:${APP_PORT}/api/health"
                    curl -fsS "http://localhost:${APP_PORT}/api/version" || true
                    curl -fsS "http://localhost:${APP_PORT}/" | grep -qi "DevOps Demo App"
                '''
            }
        }
    }

    post {
        success { echo "Deployed frontend@${env.FRONTEND_REF} + backend@${env.BACKEND_REF} at http://localhost:${env.APP_PORT}" }
        failure { echo 'Deployment failed - deploy.sh rolls back to the previous release automatically.' }
        always  { sh 'docker image prune -f --filter "until=168h" || true' }   // clean images older than 7 days
    }
}
