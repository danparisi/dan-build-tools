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
    - hostPath:
        type: Socket
        path: /run/docker.sock
      name: docker-sock
    - hostPath:
        type: Directory
        path: /var/lib/docker
      name: docker-lib
  containers:
  - name: jnlp
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 1
        memory: 4Gi
  - name: maven
    image: maven:3.9.6-eclipse-temurin-21
    tty: true
    command: [ "sleep" ]
    args: [ "infinity" ]
    volumeMounts:
    - mountPath: "/root/.m2/repository"
      name: jenkins-m2-pvc
    - mountPath: /var/run/docker.sock
      name: docker-sock
      readOnly: false
    - mountPath: /var/lib/docker
      name: docker-lib
      readOnly: false
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 1
        memory: 4Gi
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
                    env.MVN="mvn --settings settings.xml -T 1"

                    env.SERVICE_NAME=sh(script: '${MVN} help:evaluate -Dexpression=project.name -q -DforceStdout', returnStdout: true).trim()
                    env.SERVICE_VERSION=sh(script: '${MVN} help:evaluate -Dexpression=project.version -q -DforceStdout', returnStdout: true).trim()
                    env.HELM_CHART_ENABLED=sh(script: '${MVN} help:evaluate -Dexpression=helm.chart.enabled -q -DforceStdout', returnStdout: true).trim()
                    env.DOCKER_IMAGE_ENABLED=sh(script: '${MVN} help:evaluate -Dexpression=docker.image.enabled -q -DforceStdout', returnStdout: true).trim()
                    env.BUILD_NATIVE_IMAGE_ENABLED=sh(script: '${MVN} help:evaluate -Dexpression=native.image.enabled -q -DforceStdout', returnStdout: true).trim()
                    env.DOCKER_REPOSITORY_EXTERNAL_URL=sh(script: '${MVN} help:evaluate -Dexpression=docker.repository.external.url -q -DforceStdout', returnStdout: true).trim()

                    env.DOCKER_IMAGE_EXTERNAL="${env.DOCKER_REPOSITORY_EXTERNAL_URL}/repository/docker/${env.SERVICE_NAME}"
                }
            }
        }

        stage("Compilation") {
            parallel {
                stage("Build") {
                    steps {
                        sh "${MVN} clean test"
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

        stage("Build / Push Native image") {
            when { environment name: 'BUILD_NATIVE_IMAGE_ENABLED', value: 'true' }

            steps {
                sh "${MVN} -e -Pnative -DskipTests spring-boot:build-image"
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

                        sh "${MVN} helm:package helm:registry-login"

                        sh '''
                            # Need to turn off insecure flag because it creates a conflict if used along with --plain-http
                            ${MVN} helm:push -Dhelm.insecure-skip-tls-verify.enabled=false
                        '''
                    }
                }
            }
        }

        stage("Helm upgrade / Deploy") {
            when { environment name: 'HELM_CHART_ENABLED', value: 'true' }

            steps {
                sh '${MVN} helm:upgrade'
            }
        }
    }
}