pipeline {
    agent {
        kubernetes {
            cloud "kubernetes"
            defaultContainer 'maven'
            yaml '''
apiVersion: v1
kind: Pod
spec:
  volumes:
    - name: jenkins-m2-pvc
      persistentVolumeClaim:
        claimName: jenkins-m2-pvc
    - name: jenkins-docker-cache-pvc
      persistentVolumeClaim:
        claimName: jenkins-docker-cache-pvc
  containers:
  - name: maven
    image: maven:3.9.4-eclipse-temurin-17
    tty: true
    command: [ "sleep" ]
    args: [ "infinity" ]
    env:
    - name: DOCKER_HOST
      value: "tcp://localhost:2375"
    volumeMounts:
    - mountPath: "/root/.m2/repository"
      name: jenkins-m2-pvc
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  - name: docker-daemon
    image: docker:dind
    tty: true
    securityContext:
        privileged: true
    command: [  "dockerd", "--host", "tcp://127.0.0.1:2375",
                "--registry-mirror", "http://nexus-docker-proxy-http:30400",
                "--insecure-registry", "nexus-docker-proxy-http:30400",
                "--insecure-registry", "nexus-dan-helm-release-http:30600",
                "--insecure-registry", "nexus-dan-helm-snapshot-http:30601",
                "--insecure-registry", "nexus-dan-docker-release-http:30500",
                "--insecure-registry", "nexus-dan-docker-snapshot-http:30501"
             ]
    env:
    - name: DOCKER_HOST
      value: "tcp://localhost:2375"
    volumeMounts:
    - mountPath: "/tmp"
      name: jenkins-docker-cache-pvc
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
'''
        }
    }
    stages {
        stage('Checkout project') {
            steps {
                git branch: 'main', url: '${DAN_JOB_REPOSITORY}'
            }
        }

        stage("Checkout build tools") {
            steps {
                dir('dan-build-tools') {
                    git branch: 'main', url: 'https://github.com/danparisi/dan-build-tools'
                }
            }
        }

        stage('Prepare environment') {
            steps {
                sh '''
                    # Copying maven settings
                    mv dan-build-tools/maven/settings.xml .
                '''

                script {
                    env.MVN="mvn --settings settings.xml"

                    env.SERVICE_NAME=sh(script: '${MVN} help:evaluate -Dexpression=project.name -q -DforceStdout', returnStdout: true).trim()
                    env.SERVICE_VERSION=sh(script: '${MVN} help:evaluate -Dexpression=project.version -q -DforceStdout', returnStdout: true).trim()
                    env.HELM_CHART_ENABLED=sh(script: '${MVN} help:evaluate -Dexpression=helm.chart.enabled -q -DforceStdout', returnStdout: true).trim()
                    env.DOCKER_IMAGE_ENABLED=sh(script: '${MVN} help:evaluate -Dexpression=docker.image.enabled -q -DforceStdout', returnStdout: true).trim()

                    if (env.DOCKER_IMAGE_ENABLED == "true") {
                        // TODO: Release docker repo with RELEASE one if needed, currently fixed to SNAPSHOT
                        env.DOCKER_REPOSITORY_EXTERNAL=sh(script: '${MVN} help:evaluate -Dexpression=docker.repository.external -q -DforceStdout', returnStdout: true).trim()

                        env.DOCKER_IMAGE_EXTERNAL="${env.DOCKER_REPOSITORY_EXTERNAL}/repository/docker/${env.SERVICE_NAME}"
                    }
                }
            }
        }

        stage("Compilation") {
            parallel {
                stage("Build") {
                    steps {
                        sh "${MVN} clean test -T 1C"
                    }
                }
                stage("Checkstyle") {
                    steps {
                        echo "TODO: checkstyle analysis"
                    }
                }
            }
        }

        stage("Deploy maven artifact") {
            steps {
                sh "${MVN} deploy -Dmaven.test.skip -DskipTests"
            }
        }

        stage("Packaging") {
            parallel {
                stage("Docker image") {
                    when { environment name: 'DOCKER_IMAGE_ENABLED', value: 'true' }

                    steps {
                        sh '''
                            # Moving Dockerfile
                            mv dan-build-tools/Dockerfile .
                            ${MVN} dockerfile:build
                            ${MVN} dockerfile:push -Ddockerfile.username=jenkins -Ddockerfile.password=jenkins
                        '''
                   }
                }

                stage("Helm chart") {
                    when { environment name: 'HELM_CHART_ENABLED', value: 'true' }

                    steps {
                        sh '''
                            # Preparing helm chart directory
                            mv helm ${SERVICE_NAME}
                            mv dan-build-tools/helm-chart/* ${SERVICE_NAME}/
                        '''

                        sh '''
                            # Replacing placeholder in Chart.yaml
                            sed -i 's/^\\(name: \\).*$/\\1'"$SERVICE_NAME"'/' ${SERVICE_NAME}/Chart.yaml
                            sed -i 's/^\\(version: \\).*$/\\1'"$SERVICE_VERSION"'/' ${SERVICE_NAME}/Chart.yaml
                            sed -i 's/^\\(appVersion: \\).*$/\\1'"\\"$SERVICE_VERSION\\""'/' ${SERVICE_NAME}/Chart.yaml
                        '''

                        sh '''
                            # Replacing placeholder in values.yaml
                            sed -i 's~^\\(  repository: \\).*$~\\1'"$DOCKER_IMAGE_EXTERNAL"'~' ${SERVICE_NAME}/values.yaml
                            sed -i 's~^\\(  tag: \\).*$~\\1'"\\"$SERVICE_VERSION\\""'~' ${SERVICE_NAME}/values.yaml
                        '''

                        sh "${MVN} helm:init helm:dependency-build helm:lint helm:package"

                        sh "${MVN} -X helm:package helm:registry-login"

                        sh "./target/helm/helm push target/helm/repo/${SERVICE_NAME}-${SERVICE_VERSION}.tgz oci://nexus-dan-helm-snapshot-http:30601 --plain-http"
                    }
                }
            }
        }

        stage("Helm upgrade / Deploy") {
            when { environment name: 'HELM_CHART_ENABLED', value: 'true' }

            steps {
                sh '${MVN} -X helm:upgrade'
            }
        }
    }
}