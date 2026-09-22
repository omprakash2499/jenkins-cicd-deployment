pipeline {
  agent { label 'docker-aws' }
  options {
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '15'))
    skipDefaultCheckout(true)
  }
  parameters {
    string(name: 'APP_COMMIT', defaultValue: '', description: 'Full 40-character commit SHA from docker-deployment')
    string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'Terraform region output')
    string(name: 'ECR_URL', defaultValue: '', description: 'Terraform ecr_url output')
    string(name: 'INSTANCE_ID', defaultValue: '', description: 'Terraform instance_id output')
    booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Publish and request approval to deploy to AWS')
  }
  stages {
    stage('Checkout') {
      steps {
        deleteDir()
        checkout scm
        script {
          if (!(params.APP_COMMIT ==~ /[a-f0-9]{40}/)) { error('Supply a full app commit SHA') }
          if (!(params.AWS_REGION ==~ /[a-z]{2}-[a-z]+-[0-9]+/)) { error('Invalid region') }
          if (params.DEPLOY && !(params.ECR_URL ==~ /[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com\/[a-z0-9\/_-]+/)) { error('Invalid ECR URL') }
          env.IMAGE_TAG = "${params.APP_COMMIT}-${env.BUILD_NUMBER}"
              env.TEST_CONTAINER = "incident-ci-${env.BUILD_TAG}".replaceAll('[^a-zA-Z0-9_.-]', '-')
          env.DOCKER_CONFIG = "${pwd()}/.docker-auth"
        }
        dir('application') {
          checkout scmGit(branches: [[name: params.APP_COMMIT]], userRemoteConfigs: [[url: 'https://github.com/omprakash2499/docker-deployment.git']])
        }
      }
    }
    stage('Application tests') {
      steps {
        dir('application') {
          sh 'python3 -m unittest discover -s tests -v'
        }
      }
    }
    stage('Build and smoke test') {
      steps {
        sh '''#!/bin/bash
set -euo pipefail
docker build --pull --platform linux/amd64 -t "incident-api:$IMAGE_TAG" application
docker run -d --name "$TEST_CONTAINER" --read-only --tmpfs /tmp --tmpfs /data:uid=10001,gid=10001 --cap-drop ALL --security-opt no-new-privileges:true "incident-api:$IMAGE_TAG"
for attempt in {1..30}; do
  if [ "$(docker inspect --format '{{.State.Health.Status}}' "$TEST_CONTAINER")" = healthy ]; then
    docker exec "$TEST_CONTAINER" python -c "import urllib.request,json; assert isinstance(json.load(urllib.request.urlopen('http://127.0.0.1:8080/incidents')),list)"
    exit 0
  fi
  sleep 2
done
docker logs "$TEST_CONTAINER"
exit 1
'''
      }
    }
    stage('Publish immutable image') {
      when { expression { params.DEPLOY } }
      steps {
        sh '''#!/bin/bash
set -euo pipefail
mkdir -p "$DOCKER_CONFIG"
registry=${ECR_URL%%/*}
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$registry"
docker tag "incident-api:$IMAGE_TAG" "$ECR_URL:$IMAGE_TAG"
docker push "$ECR_URL:$IMAGE_TAG"
repository=${ECR_URL#*/}
digest=$(aws ecr describe-images --region "$AWS_REGION" --repository-name "$repository" --image-ids "imageTag=$IMAGE_TAG" --query 'imageDetails[0].imageDigest' --output text)
printf '%s@%s' "$ECR_URL" "$digest" > image.txt
'''
        script { env.DEPLOY_IMAGE = readFile('image.txt').trim() }
      }
    }
    stage('Approve release') {
      when { expression { params.DEPLOY } }
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          input message: "Deploy ${env.DEPLOY_IMAGE} to ${params.INSTANCE_ID}? This replaces the demo container."
        }
      }
    }
    stage('Deploy and verify') {
      when { expression { params.DEPLOY } }
      steps { sh 'python3 scripts/deploy.py' }
    }
  }
  post {
    always {
      sh 'if [ -n "${TEST_CONTAINER:-}" ]; then docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true; fi'
      sh 'rm -rf .docker-auth'
      archiveArtifacts artifacts: 'image.txt,deployment-result.json', allowEmptyArchive: true
    }
  }
}
