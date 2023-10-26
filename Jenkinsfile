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
                "--registry-mirror", "http://minikube.nexus-docker-proxy-http:30400",
                "--insecure-registry", "minikube.nexus-docker-proxy-http:30400",
                "--insecure-registry", "minikube.nexus-dan-helm-release-http:30600",
                "--insecure-registry", "minikube.nexus-dan-helm-snapshot-http:30601",
                "--insecure-registry", "minikube.nexus-dan-docker-release-http:30500",
                "--insecure-registry", "minikube.nexus-dan-docker-snapshot-http:30501"
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
                        env.DOCKER_REPOSITORY=sh(script: '${MVN} help:evaluate -Dexpression=docker.repository -q -DforceStdout', returnStdout: true).trim()
                        env.DOCKER_IMAGE="${env.DOCKER_REPOSITORY}/repository/docker/${env.SERVICE_NAME}"
                    }

                    if (env.HELM_CHART_ENABLED == "true") {
                        env.HELM_REPOSITORY_RELEASE_HOST=sh(script: '${MVN} help:evaluate -Dexpression=helm.repository.release.host -q -DforceStdout', returnStdout: true).trim()
                        env.HELM_REPOSITORY_RELEASE_PORT=sh(script: '${MVN} help:evaluate -Dexpression=helm.repository.release.port -q -DforceStdout', returnStdout: true).trim()
                        env.HELM_REPOSITORY_SNAPSHOT_HOST=sh(script: '${MVN} help:evaluate -Dexpression=helm.repository.snapshot.host -q -DforceStdout', returnStdout: true).trim()
                        env.HELM_REPOSITORY_SNAPSHOT_PORT=sh(script: '${MVN} help:evaluate -Dexpression=helm.repository.snapshot.port -q -DforceStdout', returnStdout: true).trim()
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
                            ${MVN} dockerfile:build -Ddocker.repository.host=minikube.nexus-docker-dan-snapshot-http:30501
                            ${MVN} dockerfile:push -Ddockerfile.username=jenkins -Ddockerfile.password=jenkins -Ddocker.repository.host=minikube.nexus-dan-docker-snapshot-http:30501
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
                            sed -i 's~^\\(  repository: \\).*$~\\1'"$DOCKER_IMAGE"'~' ${SERVICE_NAME}/values.yaml
                            sed -i 's~^\\(  tag: \\).*$~\\1'"\\"$SERVICE_VERSION\\""'~' ${SERVICE_NAME}/values.yaml
                        '''

                        sh "${MVN} helm:init helm:dependency-build helm:lint helm:package"

                        // https://github.com/helm/helm/issues/6324#issuecomment-1666787136
                        // Workaround needed to let helm binary push to host resolved into a local address:
                        sh '''
                            # microdnf install -y dnsutils socat
                            chmod 1777 /tmp
                            apt-get update
                            apt-get install -y dnsutils socat
                            # apk add dnsutils socat

                            HELM_REPOSITORY_RELEASE_HOST_IP=$(dig +short ${HELM_REPOSITORY_RELEASE_HOST} | head -n1)
                            HELM_REPOSITORY_SNAPSHOT_HOST_IP=$(dig +short ${HELM_REPOSITORY_SNAPSHOT_HOST} | head -n1)

                            socat TCP-LISTEN:${HELM_REPOSITORY_RELEASE_PORT},reuseaddr,fork TCP:${HELM_REPOSITORY_RELEASE_HOST_IP}:${HELM_REPOSITORY_RELEASE_PORT} &
                            socat TCP-LISTEN:${HELM_REPOSITORY_SNAPSHOT_PORT},reuseaddr,fork TCP:${HELM_REPOSITORY_SNAPSHOT_HOST_IP}:${HELM_REPOSITORY_SNAPSHOT_PORT} &

                            ${MVN} helm:package helm:registry-login helm:push -Dhelm.repository.release.host=localhost -Dhelm.repository.snapshot.host=localhost
                        '''
                    }
                }
            }
        }

        stage("Helm upgrade / Deploy") {
            when { environment name: 'HELM_CHART_ENABLED', value: 'true' }

            steps {
                sh '${MVN} helm:upgrade -Dhelm.repository.release.host=localhost -Dhelm.repository.snapshot.host=localhost'
            }
        }
    }
}