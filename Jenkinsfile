def workerLabel = 'mytardis'
def dockerHubAccount = 'mytardis'
def dockerImageName = 'k8s-mytardis'
def dockerImageTag = ''
def dockerImageFullNameTag = ''
def dockerImageFullNameLatest = "${dockerHubAccount}/${dockerImageName}:latest"
def k8sDeploymentNamespace = 'mytardis'
def gitInfo = ''
def gitVersion = ''

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
            image: 'postgres:9.3',
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
        secretVolume(secretName: 'kube-config-test', mountPath: '/tmp/kube'),
        secretVolume(secretName: 'docker-config', mountPath: '/tmp/docker'),
        hostPathVolume(hostPath: '/var/run/docker.sock', mountPath: '/var/run/docker.sock')
    ]
) {
    node(workerLabel) {
        def ip = sh(returnStdout: true, script: 'hostname -i').trim()
        stage('Clone repository') {
            checkout scm
            sh("git submodule update --init --recursive")
        }
        dockerImageTag = sh(returnStdout: true, script: 'git log -n 1 --pretty=format:"%h"').trim()
        dockerImageFullNameTag = "${dockerHubAccount}/${dockerImageName}:${dockerImageTag}"
        dir('submobules/mytardis') {
            gitInfo = [
                'commit_id': sh(returnStdout: true, script: 'git log -n 1 --pretty=format:"%H"').trim(),
                'date': sh(returnStdout: true, script: 'git log -n 1 --pretty=format:"%cd" --date=rfc').trim(),
                'branch': sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim(),
                'tag': ''
            ]
            try {
                gitInfo['tag'] = sh(returnStdout: true, script: 'git describe --abbrev=0 --tags').trim()
            } catch(Exception e) {}
        }
        gitVersion = '{\\"data\\":{\\"version\\":\\"' + gitInfo.inspect().replace("'", '\\\"').replace('[', '{').replace(']', '}') + '\\"}}'
        echo "gitVersion: ${gitVersion}"
        stage('Patch configMap') {
            container('kubectl') {
                sh("kubectl -n ${k8sDeploymentNamespace} patch configmap/version -p \"" + gitVersion.replace('"', '\\"') + "\"")
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
            'behave': "docker run ${dockerImageFullNameTag} python manage.py behave --settings=tardis.test_settings",
            'pylint': "docker run ${dockerImageFullNameTag} pylint --rcfile .pylintrc tardis",
            'memory': "docker run ${dockerImageFullNameTag} python test.py test --settings=tardis.test_settings",
            'postgres': "docker run --add-host pg:${ip} ${dockerImageFullNameTag} python test.py test --settings=tardis.test_on_postgresql_settings",
            'mysql': "docker run --add-host mysql:${ip} ${dockerImageFullNameTag} python test.py test --settings=tardis.test_on_mysql_settings"
        ].each { name, command ->
            tests[name] = {
                stage("Run test - ${name}") {
                    container('docker') {
                        sh(command)
                    }
                }
            }
        }
        // parallel tests
        stage('Build image for production') {
            container('docker') {
                sh("docker build . --tag ${dockerImageFullNameTag} --target=production")
            }
        }
        stage('Push image to DockerHub') {
            container('docker') {
                sh("docker push ${dockerImageFullNameTag}")
                sh("docker tag ${dockerImageFullNameTag} ${dockerImageFullNameLatest}")
                sh("docker push ${dockerImageFullNameLatest}")
            }
        }
        stage('Deploy image to Kubernetes') {
            container('kubectl') {
                ['migrate', 'collectstatic'].each { item ->
                    sh("kubectl -n ${k8sDeploymentNamespace} delete job/${item} --ignore-not-found")
                    sh("kubectl create -f jobs/${item}.yaml")
                    sh("kubectl -n ${k8sDeploymentNamespace} wait --for=condition=complete --timeout=240s job/${item}")
                }
                sh("kubectl -n ${k8sDeploymentNamespace} patch configmap/version -p \"" + gitVersion.replace('"', '\"') + "\"")
                ['mytardis', 'sftp', 'celery-worker', 'celery-beat'].each { item ->
                    sh("kubectl -n ${k8sDeploymentNamespace} set image deployment/${item} ${item}=${dockerImageFullNameTag}")
                }
            }
        }
    }
}
