module repo

import os
import package
import util

// Manages a group of repositories. Each repository contains one or more
// arch-repositories, each of which represent a specific architecture.
pub struct RepoGroupManager {
mut:
	mutex shared util.Dummy
pub:
	// Where to store repositories' files
	repos_dir string [required]
	// Where packages are stored; each arch-repository gets its own
	// subdirectory
	pkg_dir string [required]
	// The default architecture to use for a repository. Whenever a package of
	// arch "any" is added to a repo, it will also be added to this
	// architecture.
	default_arch string [required]
}

pub struct RepoAddResult {
pub:
	added bool         [required]
	pkg   &package.Pkg [required]
}

// new creates a new RepoGroupManager & creates the directories as needed
pub fn new(repos_dir string, pkg_dir string, default_arch string) ?RepoGroupManager {
	if !os.is_dir(repos_dir) {
		os.mkdir_all(repos_dir) or { return error('Failed to create repos directory: $err.msg') }
	}

	if !os.is_dir(pkg_dir) {
		os.mkdir_all(pkg_dir) or { return error('Failed to create package directory: $err.msg') }
	}

	return RepoGroupManager{
		repos_dir: repos_dir
		pkg_dir: pkg_dir
		default_arch: default_arch
	}
}

// add_pkg_from_path adds a package to a given repo, given the file path to the
// pkg archive. It's a wrapper around add_pkg_in_repo that parses the archive
// file, passes the result to add_pkg_in_repo, and hard links the archive to
// the right subdirectories in r.pkg_dir if it was successfully added.
pub fn (r &RepoGroupManager) add_pkg_from_path(repo string, pkg_path string) ?RepoAddResult {
	pkg := package.read_pkg_archive(pkg_path) or {
		return error('Failed to read package file: $err.msg')
	}

	added := r.add_pkg_in_repo(repo, pkg) ?

	// If the add was successful, we move the file to the packages directory
	for arch in added {
		repo_pkg_path := os.real_path(os.join_path(r.pkg_dir, repo, arch))
		dest_path := os.join_path_single(repo_pkg_path, pkg.filename())

		os.mkdir_all(repo_pkg_path) ?

		// We create hard links so that "any" arch packages aren't stored
		// multiple times
		os.link(pkg_path, dest_path) ?
	}

	// After linking, we can remove the original file
	os.rm(pkg_path) ?

	return RepoAddResult{
		added: added.len > 0
		pkg: &pkg
	}
}

// add_pkg_in_repo adds a package to a given repo. This function is responsible
// for inspecting the package architecture. If said architecture is 'any', the
// package is added to each arch-repository within the given repo. A package of
// architecture 'any' is always added to the arch-repo defined by
// r.default_arch. If this arch-repo doesn't exist yet, it is created. If the
// architecture isn't 'any', the package is only added to the specific
// architecture.
fn (r &RepoGroupManager) add_pkg_in_repo(repo string, pkg &package.Pkg) ?[]string {
	// A package not of arch 'any' can be handled easily by adding it to the
	// respective repo
	if pkg.info.arch != 'any' {
		if r.add_pkg_in_arch_repo(repo, pkg.info.arch, pkg) ? {
			return [pkg.info.arch]
		} else {
			return []
		}
	}

	mut arch_repos := []string{}

	// If it is an "any" package, the package gets added to every currently
	// present arch-repo. It will always get added to the r.default_arch repo,
	// even if no or multiple others are present.
	repo_dir := os.join_path_single(r.repos_dir, repo)

	// If this is the first package that's added to the repo, the directory
	// won't exist yet
	if os.exists(repo_dir) {
		arch_repos = os.ls(repo_dir) ?
	}

	// The default_arch should always be updated when a package with arch 'any'
	// is added.
	if !arch_repos.contains(r.default_arch) {
		arch_repos << r.default_arch
	}

	mut added := []string{}

	// We add the package to each repository. If any of the repositories
	// return true, the result of the function is also true.
	for arch in arch_repos {
		if r.add_pkg_in_arch_repo(repo, arch, pkg) ? {
			added << arch
		}
	}

	return added
}

// add_pkg_in_arch_repo is the function that actually adds a package to a given
// arch-repo. It records the package's data in the arch-repo's desc & files
// files, and afterwards updates the db & files archives to reflect these
// changes. The function returns false if the package was already present in
// the repo, and true otherwise.
fn (r &RepoGroupManager) add_pkg_in_arch_repo(repo string, arch string, pkg &package.Pkg) ?bool {
	pkg_dir := os.join_path(r.repos_dir, repo, arch, '$pkg.info.name-$pkg.info.version')

	// Remove the previous version of the package, if present
	r.remove_pkg_from_arch_repo(repo, arch, pkg.info.name, false) ?

	os.mkdir_all(pkg_dir) or { return error('Failed to create package directory.') }

	os.write_file(os.join_path_single(pkg_dir, 'desc'), pkg.to_desc()) or {
		os.rmdir_all(pkg_dir) ?

		return error('Failed to write desc file.')
	}
	os.write_file(os.join_path_single(pkg_dir, 'files'), pkg.to_files()) or {
		os.rmdir_all(pkg_dir) ?

		return error('Failed to write files file.')
	}

	r.sync(repo, arch) ?

	return true
}

// remove_pkg_from_arch_repo removes a package from an arch-repo's database. It
// returns false if the package wasn't present in the database. It also
// optionally re-syncs the repo archives.
fn (r &RepoGroupManager) remove_pkg_from_arch_repo(repo string, arch string, pkg_name string, sync bool) ?bool {
	repo_dir := os.join_path(r.repos_dir, repo, arch)

	// If the repository doesn't exist yet, the result is automatically false
	if !os.exists(repo_dir) {
		return false
	}

	// We iterate over every directory in the repo dir
	// TODO filter so we only check directories
	for d in os.ls(repo_dir) ? {
		// Because a repository only allows a single version of each package,
		// we need only compare whether the name of the package is the same,
		// not the version.
		name := d.split('-')#[..-2].join('-')

		if name == pkg_name {
			// We lock the mutex here to prevent other routines from creating a
			// new archive while we remove an entry
			lock r.mutex {
				os.rmdir_all(os.join_path_single(repo_dir, d)) ?
			}

			// Also remove the package archive
			repo_pkg_dir := os.join_path(r.pkg_dir, repo, arch)

			archives := os.ls(repo_pkg_dir) ?.filter(it.split('-')#[..-3].join('-') == name)

			for archive_name in archives {
				full_path := os.join_path_single(repo_pkg_dir, archive_name)
				os.rm(full_path) ?
			}

			// Sync the db archives if requested
			if sync {
				r.sync(repo, arch) ?
			}

			return true
		}
	}

	return false
}
