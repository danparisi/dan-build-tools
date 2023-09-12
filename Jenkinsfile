podTemplate(
    containers: [
        containerTemplate(
            name: 'maven',
            image: 'maven:3.8.3-openjdk-17',
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
                    stage('Checkout') {
                        sh "ls -la"

                        git branch: 'main', url: '${DAN_JOB_REPOSITORY}'

                        sh "ls -la"
                    }

                    stage('Prepare environment') {
                        container('maven') {
                            env.SERVICE_NAME=sh(script: 'mvn help:evaluate -Dexpression=project.name -q -DforceStdout', returnStdout: true).trim()
                            env.SERVICE_VERSION=sh(script: 'mvn help:evaluate -Dexpression=project.version -q -DforceStdout', returnStdout: true).trim()

                            // TODO: Release docker repo with RELEASE one if needed, currently fixed to SNAPSHOT
                            env.DOCKER_REPOSITORY=sh(script: 'mvn help:evaluate -Dexpression=docker.repository -q -DforceStdout', returnStdout: true).trim()
                            env.DOCKER_IMAGE="${env.DOCKER_REPOSITORY}/repository/docker/${env.SERVICE_NAME}"

                            env.HELM_REPOSITORY_RELEASE_HOST=sh(script: 'mvn help:evaluate -Dexpression=helm.repository.release.host -q -DforceStdout', returnStdout: true).trim()
                            env.HELM_REPOSITORY_RELEASE_PORT=sh(script: 'mvn help:evaluate -Dexpression=helm.repository.release.port -q -DforceStdout', returnStdout: true).trim()
                            env.HELM_REPOSITORY_SNAPSHOT_HOST=sh(script: 'mvn help:evaluate -Dexpression=helm.repository.snapshot.host -q -DforceStdout', returnStdout: true).trim()
                            env.HELM_REPOSITORY_SNAPSHOT_PORT=sh(script: 'mvn help:evaluate -Dexpression=helm.repository.snapshot.port -q -DforceStdout', returnStdout: true).trim()
                        }
                    }

                    stage("Compilation") {
                         container('maven') {
                             parallel 'Build and Test': {
                                 sh "mvn clean install -DskipTests"
                             }, 'Static Analysis': {
                                 stage("Checkstyle") {
                                    echo "Skipping checkstyle analysis"
                                 }
                             }
                         }
                    }

                    stage("Configuring build tools") {
                         container('maven') {
                            dir('dan-build-tools') {
                                git branch: 'main', url: 'https://github.com/danparisi/dan-build-tools'
                            }
                            sh "ls -la"
                            sh "mv helm ${SERVICE_NAME}"
                            sh "mv dan-build-tools/helm-chart/* ${SERVICE_NAME}/"
                            sh "ls -la ${SERVICE_NAME}/"

                            sh "mv dan-build-tools/Dockerfile ."

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

                            sh "ls -la ${SERVICE_NAME}"

                            sh "cat ${SERVICE_NAME}/Chart.yaml"
                            sh "cat ${SERVICE_NAME}/values.yaml"

                            sh "ls -la"
                        }
                    }

                    stage("Packaging") {
                         container('maven') {
                             parallel 'Docker': {
                                stage("Build") {
                                     container('maven') {
                                        sh "mvn dockerfile:build -Ddocker.repository.host=minikube.nexus-docker-dan-snapshot-http:30501"
                                     }
                                }

                                stage("Push") {
                                     container('maven') {
                                        sh "mvn dockerfile:push -Ddockerfile.username=jenkins -Ddockerfile.password=jenkins -Ddocker.repository.host=minikube.nexus-dan-docker-snapshot-http:30501"
                                     }
                                }

                            },
                            'Helm': {
                                stage("Package") {
                                     container('maven') {
                                        sh "mvn helm:init helm:dependency-build helm:lint helm:package"
                                     }
                                }

                                stage("Push") {
                                     container('maven') {
                                        // https://github.com/helm/helm/issues/6324#issuecomment-1666787136
                                        // Workaround needed to let helm binary push to host resolved into a local address:

                                         sh '''
                                                microdnf install -y dnsutils socat

                                                HELM_REPOSITORY_RELEASE_HOST_IP=$(dig +short ${HELM_REPOSITORY_RELEASE_HOST} | head -n1)
                                                HELM_REPOSITORY_SNAPSHOT_HOST_IP=$(dig +short ${HELM_REPOSITORY_SNAPSHOT_HOST} | head -n1)

                                                socat TCP-LISTEN:${HELM_REPOSITORY_RELEASE_PORT},reuseaddr,fork TCP:${HELM_REPOSITORY_RELEASE_HOST_IP}:${HELM_REPOSITORY_RELEASE_PORT} &
                                                socat TCP-LISTEN:${HELM_REPOSITORY_SNAPSHOT_PORT},reuseaddr,fork TCP:${HELM_REPOSITORY_SNAPSHOT_HOST_IP}:${HELM_REPOSITORY_SNAPSHOT_PORT} &

                                                mvn helm:package helm:registry-login helm:push -Dhelm.repository.release.host=localhost -Dhelm.repository.snapshot.host=localhost
                                            '''
                                     }
                                }

                            }
                        }
                    }

                    stage("Helm upgrade / Deploy") {
                         container('maven') {
                            sh 'mvn helm:upgrade -Dhelm.repository.release.host=localhost -Dhelm.repository.snapshot.host=localhost'
                            //sh "/home/jenkins/agent/workspace/dan-shop-core/target/helm/helm upgrade dan-shop-core-service ${HELM_REPOSITORY_SNAPSHOT_HOST_IP}:${HELM_REPOSITORY_SNAPSHOT_PORT}/dan-shop-core-service --version=0.0.1-SNAPSHOT --install --force"
                            //sh "/home/jenkins/agent/workspace/dan-shop-core/target/helm/helm upgrade dan-shop-core-service oci://localhost:${HELM_REPOSITORY_SNAPSHOT_PORT}/dan-shop-core-service --version=0.0.1-SNAPSHOT --install --force"
                         }
                    }
                 }
            }
}
