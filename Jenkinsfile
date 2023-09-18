podTemplate(
    containers: [
        containerTemplate(
            name: 'maven',
            image: 'maven:3.9.4-eclipse-temurin-17',
            command: '/bin/sh',
            args: '-c "sleep 99d"',
            envVars: [
                containerEnvVar(key: 'DOCKER_HOST', value: "tcp://localhost:2375")
            ]
        )
    ], volumes: [
        persistentVolumeClaim(
            mountPath: '/root/.m2/repository',
            claimName: 'jenkins-m2-pvc',
            readOnly: false
        )]) {
            podTemplate(
                containers: [containerTemplate(
                    image: 'docker:dind',
                    name: 'docker-daemon',
                    command: 'dockerd --host tcp://127.0.0.1:2375 --registry-mirror http://minikube.nexus-docker-proxy-http:30400 --insecure-registry minikube.nexus-docker-proxy-http:30400 --insecure-registry minikube.nexus-dan-docker-release-http:30500 --insecure-registry minikube.nexus-dan-docker-snapshot-http:30501 --insecure-registry minikube.nexus-dan-helm-release-http:30600 --insecure-registry minikube.nexus-dan-helm-snapshot-http:30601',
                    privileged: true,
                    ttyEnabled: true,
                    envVars: [
                        containerEnvVar(key: 'DOCKER_TLS_VERIFY', value: ""),
                        containerEnvVar(key: 'DOCKER_TLS_CERTDIR', value: ""),
                        containerEnvVar(key: 'DOCKER_HOST', value: "tcp://localhost:2375")
                    ]
            )], volumes: [
                persistentVolumeClaim(
                    mountPath: '/tmp',
                    claimName: 'jenkins-docker-cache-pvc',
                    readOnly: false
                )
            ]) {
                 node(POD_LABEL) {
                    stage('Checkout project') {
                        git branch: 'main', url: '${DAN_JOB_REPOSITORY}'
                    }

                    stage("Checkout build tools") {
                         container('maven') {
                            dir('dan-build-tools') {
                                git branch: 'main', url: 'https://github.com/danparisi/dan-build-tools'
                            }
                         }
                    }

                    stage('Prepare environment') {
                        container('maven') {
                            sh '''
                                # Copying maven settings
                                mv dan-build-tools/maven/settings.xml .
                            '''

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

                    stage("Compilation") {
                         container('maven') {
                             parallel 'Build and Test': {
                                 sh "${MVN} clean test"
                             }, 'Static Analysis': {
                                 stage("Checkstyle") {
                                    echo "Skipping checkstyle analysis"
                                 }
                             }
                         }
                    }

                    stage("Deploy maven artifact") {
                         container('maven') {
                            sh "${MVN} deploy -DskipTests"
                         }
                    }

                    stage("Configuring build tools") {
                         container('maven') {
                            if (env.DOCKER_IMAGE_ENABLED == "true") {
                                sh '''
                                    # Moving Dockerfile
                                    mv dan-build-tools/Dockerfile .
                                '''
                            } else {
                                sh "echo 'Skipping Dockerfile preparation'"
                            }

                            if (env.HELM_CHART_ENABLED == "true") {
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
                            } else {
                                sh "echo 'Skipping helm chart preparation'"
                            }
                        }
                    }

                    stage("Packaging") {
                        parallel 'Docker':
                        {
                            stage("Docker image") {
                                container('maven') {
                                    if (env.DOCKER_IMAGE_ENABLED == "true") {
                                        sh "${MVN} dockerfile:build -Ddocker.repository.host=minikube.nexus-docker-dan-snapshot-http:30501"
                                        sh "${MVN} dockerfile:push -Ddockerfile.username=jenkins -Ddockerfile.password=jenkins -Ddocker.repository.host=minikube.nexus-dan-docker-snapshot-http:30501"
                                    } else {
                                        sh "echo 'Skipping Docker image build & push'"
                                    }
                               }
                            }
                        }, 'Helm':
                        {
                            stage("Helm chart") {
                                container('maven') {
                                    if (env.HELM_CHART_ENABLED == "true") {
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
                                    } else {
                                        sh "echo 'Skipping Helm chart package & push'"
                                    }
                                }
                            }
                        }
                    }

                    stage("Helm upgrade / Deploy") {
                        container('maven') {
                            if (env.HELM_CHART_ENABLED == "true") {
                                sh '${MVN} helm:upgrade -Dhelm.repository.release.host=localhost -Dhelm.repository.snapshot.host=localhost'
                            } else {
                                sh "echo 'Skipping Helm chart upgrade'"
                            }
                        }
                    }
                 }
            }
}
