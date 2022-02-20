module main

import docker
import encoding.base64
import rand
import time
import os
import json
import git

const container_build_dir = '/build'

fn build(key string, repo_dir string) ? {
	server_url := os.getenv_opt('VIETER_ADDRESS') or { exit_with_message(1, 'No Vieter server address was provided.') }

	// Read in the repos from a json file
	filename := os.join_path_single(repo_dir, 'repos.json')
	txt := os.read_file(filename) ?
	repos := json.decode([]git.GitRepo, txt) ?

	mut commands := [
		// Update repos & install required packages
		'pacman -Syu --needed --noconfirm base-devel git'
		// Add a non-root user to run makepkg
		'groupadd -g 1000 builder'
		'useradd -mg builder builder'
		// Make sure they can use sudo without a password
		"echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers"
		// Create the directory for the builds & make it writeable for the
		// build user
		'mkdir /build'
		'chown -R builder:builder /build'
	]

	// Each repo gets a unique UUID to avoid naming conflicts when cloning
	mut uuids := []string{}

	for repo in repos {
		mut uuid := rand.uuid_v4()

		// Just to be sure we don't have any collisions
		for uuids.contains(uuid) {
			uuid = rand.uuid_v4()
		}

		uuids << uuid

		commands << "su builder -c 'git clone --single-branch --depth 1 --branch $repo.branch $repo.url /build/$uuid'"
		commands << 'su builder -c \'cd /build/$uuid && makepkg -s --noconfirm --needed && for pkg in \$(ls -1 *.pkg*); do curl -XPOST -T "\${pkg}" -H "X-API-KEY: \$API_KEY" $server_url/publish; done\''
	}

	// We convert the list of commands into a base64 string, which then gets
	// passed to the container as an env var
	cmds_str := base64.encode_str(commands.join('\n'))

	c := docker.NewContainer{
		image: 'archlinux:latest'
		env: ['BUILD_SCRIPT=$cmds_str', 'API_KEY=$key']
		entrypoint: ['/bin/sh', '-c']
		cmd: ['echo \$BUILD_SCRIPT | base64 -d | /bin/sh -e']
	}

	// First, we pull the latest archlinux image
	docker.pull_image('archlinux', 'latest') ?

	id := docker.create_container(c) ?
	docker.start_container(id) ?

	// This loop waits until the container has stopped, so we can remove it after
	for {
		data := docker.inspect_container(id) ?

		if !data.state.running {
			break
		}

		// Wait for 5 seconds
		time.sleep(5000000000)
	}

	docker.remove_container(id) ?
}
