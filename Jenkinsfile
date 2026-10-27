// Declarative Jenkins pipeline that builds and deploys the full app
// (frontend repo + backend repo) by calling deploy.sh.
//
// Prerequisites on the Jenkins agent (Ubuntu):
//   - docker + docker compose plugin; the 'jenkins' user is in the 'docker' group
//   - git, curl
//   - this file + deploy.sh + docker-compose.yml are in the repo Jenkins checks out
//   - (private repos) a 'git-credentials' credential of type "SSH key" or "username/password"
//
pipeline {
    agent any

    parameters {
        string(name: 'FRONTEND_REPO', defaultValue: 'https://github.com/<your-user>/demo-frontend.git', description: 'Frontend git URL')
        string(name: 'BACKEND_REPO',  defaultValue: 'https://github.com/<your-user>/demo-backend.git',  description: 'Backend git URL')
        string(name: 'FRONTEND_REF',  defaultValue: 'main', description: 'Frontend commit SHA / branch / tag')
        string(name: 'BACKEND_REF',   defaultValue: 'main', description: 'Backend commit SHA / branch / tag')
        string(name: 'APP_PORT',      defaultValue: '8080', description: 'Host port to publish the app on')
    }

    options {
        timestamps()
        disableConcurrentBuilds()          // never run two deployments at once
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    // Optional: build automatically when GitHub pushes (configure a webhook -> /github-webhook/)
    // triggers { githubPush() }
    // ...or poll every 5 minutes as a fallback:
    // triggers { pollSCM('H/5 * * * *') }

    environment {
        WORKSPACE_DIR = "${env.JENKINS_HOME}/deploy-workspace"
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
        success { echo "Deployed frontend@${params.FRONTEND_REF} + backend@${params.BACKEND_REF}" }
        failure { echo 'Deployment failed - deploy.sh rolls back to the previous release automatically.' }
        always  { sh 'docker image prune -f --filter "until=168h" || true' }   // clean images older than 7 days
    }
}
