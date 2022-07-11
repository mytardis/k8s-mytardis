def workerLabel = 'mytardis-qat'
def dockerHubAccount = 'mytardis'
def dockerImageName = 'k8s-mytardis-qat'
def dockerImageTag = ''
def dockerImageFullNameTag = ''
def k8sDeploymentNamespace = 'mytardis'
def gitInfo = ''

def updateProperty(property, value, file) {
    escapedProperty = property.replace('[', '\\[').replace(']', '\\]').replace('.', '\\.')
    sh("sed -i 's|$escapedProperty|$value|g' $file")
}

podTemplate(
    label: workerLabel,
    serviceAccount: 'jenkins',
    automountServiceAccountToken: true,
    containers: [
        containerTemplate(
            name: 'docker',
            image: 'docker:18.06.2-ce-dind',
            ttyEnabled: true,
            command: 'cat',
            envVars: [
                containerEnvVar(key: 'DOCKER_CONFIG', value: '/tmp/docker')
            ],
            resourceRequestCpu: '1000m',
            resourceRequestMemory: '2Gi'
        ),
        containerTemplate(
            name: 'mysql',
            image: 'mysql:5.7',
            alwaysPullImage: false,
            envVars: [
                envVar(key: 'MYSQL_ROOT_PASSWORD', value: 'mysql')
            ]
        ),
        containerTemplate(
            name: 'postgres',
            image: 'postgres:9.6',
            alwaysPullImage: false,
            envVars: [
                envVar(key: 'POSTGRES_PASSWORD', value: 'postgres')
            ]
        ),
        containerTemplate(
            name: 'kubectl',
            image: 'lachlanevenson/k8s-kubectl:v1.13.0',
            ttyEnabled: true,
            command: 'cat',
            envVars: [
                containerEnvVar(key: 'KUBECONFIG', value: '/tmp/kube/admin.conf')
            ]
        )
    ],
    volumes: [
        secretVolume(secretName: 'kube-config-qat', mountPath: '/tmp/kube'),
        secretVolume(secretName: 'docker-config', mountPath: '/tmp/docker'),
        hostPathVolume(hostPath: '/var/run/docker.sock', mountPath: '/var/run/docker.sock')
    ]
) {
    node(workerLabel) {
        def ip = sh(returnStdout: true, script: 'hostname -i').trim()
        stage('Clone repository') {
            checkout scm
            // git url: 'https://github.com/mytardis/k8s-mytardis', branch: 'master'
            sh("git submodule update --init --recursive")
        }
        dockerImageTag = sh(returnStdout: true, script: 'git log -n 1 --pretty=format:"%h"').trim()
        dockerImageFullNameTag = "${dockerHubAccount}/${dockerImageName}:${dockerImageTag}"
        dir('submodules/mytardis') {
            gitInfo = [
                'commit_id': sh(returnStdout: true, script: 'git log -n 1 --pretty=format:"%H"').trim(),
                'date': sh(returnStdout: true, script: 'git log -n 1 --pretty=format:"%cd" --date=rfc').trim(),
                'branch': sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim(),
                'tag': ''
            ]
            try {
                gitInfo['tag'] = sh(returnStdout: true, script: 'git describe --abbrev=0 --tags').trim()
            } catch(Exception e) {
                gitInfo['tag'] = sh(returnStdout: true, script: 'git log -n 1 --pretty=format:"%h"').trim()
            }
        }
        stage('Build image for tests') {
            container('docker') {
                sh("docker build . --tag ${dockerImageFullNameTag} --target=test")
            }
        }
        def tests = [:]
        [
            'npm': "docker run ${dockerImageFullNameTag} npm test",
            // 'behave': "docker run ${dockerImageFullNameTag} python3 manage.py behave --settings=tardis.test_settings",
            // 'pylint': "docker run ${dockerImageFullNameTag} pylint --rcfile .pylintrc --django-settings-module=tardis.test_settings tardis",
            'memory': "docker run ${dockerImageFullNameTag} python3 test.py test --settings=tardis.test_settings",
            'postgres': "docker run --add-host pg:${ip} ${dockerImageFullNameTag} python3 test.py test --settings=tardis.test_on_postgresql_settings",
            // 'mysql': "docker run --add-host mysql:${ip} ${dockerImageFullNameTag} python3 test.py test --settings=tardis.test_on_mysql_settings"
        ].each { name, command ->
            tests[name] = {
                stage("Run test - ${name}") {
                    container('docker') {
                        sh(command)
                    }
                }
            }
        }
        parallel tests
        stage('Build image for qat') {
            container('docker') {
                sh("docker build . --tag ${dockerImageFullNameTag} --target=production")
            }
        }
        stage('Push image to DockerHub') {
            container('docker') {
                sh("docker push ${dockerImageFullNameTag}")
            }
        }
        stage('Deploy image to Kubernetes') {
            container('kubectl') {
                dir('jobs') {
                    ['migrate', 'collectstatic'].each { item ->
                        updateProperty(":[dockerImageFullNameTag]", dockerImageFullNameTag, "${item}.yaml")
                        sh("kubectl -n ${k8sDeploymentNamespace} delete job/${item} --ignore-not-found")
                        sh("kubectl create -f ${item}.yaml")
                        sh("kubectl -n ${k8sDeploymentNamespace} wait --for=condition=complete --timeout=480s job/${item}")
                    }
                }
                def patch = '{"data":{"version":"' + gitInfo.inspect().replace('[', '{').replace(']', '}') + '"}}'
                echo "patch: ${patch}"
                sh("kubectl -n ${k8sDeploymentNamespace} patch configmap/version -p '" + patch.replace("'", '\\"') + "'")
                ['mytardis', 'sftp', 'celery-worker', 'celery-beat'].each { item ->
                    sh("kubectl -n ${k8sDeploymentNamespace} set image deployment/${item} ${item}=${dockerImageFullNameTag}")
                }
            }
        }
    }
}
