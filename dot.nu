#!/usr/bin/env nu

source scripts/kubernetes.nu
source scripts/common.nu
source scripts/ingress.nu

def main [] {}

def "main setup" [] {

    main delete temp_files

    let hyperscaler = main get hyperscaler

    create kubernetes $hyperscaler

    let ingress_data = (
        main apply ingress contour --hyperscaler $hyperscaler
    )

    apply karpor

    apply apps

    apply headlamp $"headlamp.($ingress_data.host)"

    main print source

}

def "main destroy" [
    hyperscaler: string
] {

    (
        main destroy kubernetes $hyperscaler --name dot01
            --delete_project false
    )

    (
        main destroy kubernetes $hyperscaler --name dot02
            --delete_project false
    )

    main destroy kubernetes $hyperscaler --name dot03

}

def --env "create kubernetes" [
    hyperscaler: string
] {

    (
        main create kubernetes $hyperscaler --name dot01
            --min_nodes 2 --node_size medium
    )

    (
        main create kubernetes $hyperscaler --name dot02
            --auth false --min_nodes 1
    )

    (
        main create kubernetes $hyperscaler --name dot03
            --auth false --min_nodes 1
    )

    $env.KUBECONFIG = $"($env.PWD)/kubeconfig-dot01.yaml"
    $"export KUBECONFIG=($env.KUBECONFIG)\n" | save --append .env

    if $hyperscaler == "aws" or $hyperscaler == "google" {

        for kubeconfig in [
            "kubeconfig-dot01.yaml"
            "kubeconfig-dot02.yaml"
            "kubeconfig-dot03.yaml"
        ] {(
            main create kubernetes_creds
                --source_kuberconfig $kubeconfig
                --destination_kuberconfig $kubeconfig
        )}

    }

}

def --env "apply headlamp" [
    host: string
] {

    helm repo add headlamp https://headlamp-k8s.github.io/headlamp/

    helm repo update

    {
        ingress: {
            enabled: true
            ingressClassName: "contour"
            hosts: [{
                host: $host
                paths: [{
                    path: "/"
                    type: "ImplementationSpecific"
                }]
            }]
        }
    } | to yaml | save headlamp-values.yaml --force

    (
        helm upgrade --install headlamp headlamp/headlamp
            --set ingress.enabled=true
            --values headlamp-values.yaml
            --namespace headlamp --create-namespace --wait
    )

    let token = kubectl --namespace headlamp create token headlamp
    $"export HEADLAMP_TOKEN=($token)\n"
        | save --append .env

    print $"
Use the (ansi yellow_bold)token(ansi reset) that follows to login to headlamp:
------------------
$($token)
------------------
"
    start $"http://($host)"

    print $"
Press (ansi yellow_bold)any key(ansi reset) to continue.
    "
    input

}

def --env "apply karpor" [] {

    helm repo add kusionstack https://kusionstack.github.io/charts

    helm repo update

    helm upgrade --install karpor-release kusionstack/karpor --wait

    echo "https://127.0.0.1:7443"

}

def --env "apply apps" [] {

    (
        kubectl --kubeconfig kubeconfig-dot01.yaml
            create namespace a-team
    )

    (
        kubectl --kubeconfig kubeconfig-dot01.yaml apply
            --namespace a-team --filename a-team
    )

    (
        kubectl --kubeconfig kubeconfig-dot02.yaml
            create namespace a-team
    )

    (
        kubectl --kubeconfig kubeconfig-dot02.yaml apply
            --namespace a-team --filename a-team
    )

    (
        kubectl --kubeconfig kubeconfig-dot03.yaml
            create namespace production
    )

    (
        kubectl --kubeconfig kubeconfig-dot03.yaml apply
            --namespace production --filename b-team
    )

}

