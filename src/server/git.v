module server

import web
import git
import net.http
import rand
import response { new_data_response, new_response }
import db

const repos_file = 'repos.json'

// get_repos returns the current list of repos.
['/api/repos'; get]
fn (mut app App) get_repos() web.Result {
	if !app.is_authorized() {
		return app.json(http.Status.unauthorized, new_response('Unauthorized.'))
	}

	repos := app.db.get_git_repos()
	// repos := rlock app.git_mutex {
	//	git.read_repos(app.conf.repos_file) or {
	//		app.lerror('Failed to read repos file: $err.msg()')

	//		return app.status(http.Status.internal_server_error)
	//	}
	//}

	return app.json(http.Status.ok, new_data_response(repos))
}

// get_single_repo returns the information for a single repo.
['/api/repos/:id'; get]
fn (mut app App) get_single_repo(id int) web.Result {
	if !app.is_authorized() {
		return app.json(http.Status.unauthorized, new_response('Unauthorized.'))
	}

	// repos := rlock app.git_mutex {
	//	git.read_repos(app.conf.repos_file) or {
	//		app.lerror('Failed to read repos file.')

	//		return app.status(http.Status.internal_server_error)
	//	}
	//}

	// if id !in repos {
	//	return app.not_found()
	//}

	// repo := repos[id]
	repo := app.db.get_git_repo(id) or { return app.not_found() }

	return app.json(http.Status.ok, new_data_response(repo))
}

// post_repo creates a new repo from the provided query string.
['/api/repos'; post]
fn (mut app App) post_repo() web.Result {
	if !app.is_authorized() {
		return app.json(http.Status.unauthorized, new_response('Unauthorized.'))
	}

	mut params := app.query.clone()

	// If a repo is created without specifying the arch, we assume it's meant
	// for the default architecture.
	if 'arch' !in params {
		params['arch'] = app.conf.default_arch
	}

	new_repo := db.git_repo_from_params(params) or {
		return app.json(http.Status.bad_request, new_response(err.msg()))
	}

	app.db.add_git_repo(new_repo)

	// id := rand.uuid_v4()

	// mut repos := rlock app.git_mutex {
	//	git.read_repos(app.conf.repos_file) or {
	//		app.lerror('Failed to read repos file.')

	//		return app.status(http.Status.internal_server_error)
	//	}
	//}
	// repos := app.db.get_git_repos()

	//// We need to check for duplicates
	// for _, repo in repos {
	//	if repo == new_repo {
	//		return app.json(http.Status.bad_request, new_response('Duplicate repository.'))
	//	}
	//}

	// repos[id] = new_repo

	// lock app.git_mutex {
	//	git.write_repos(app.conf.repos_file, &repos) or {
	//		return app.status(http.Status.internal_server_error)
	//	}
	//}

	return app.json(http.Status.ok, new_response('Repo added successfully.'))
}

// delete_repo removes a given repo from the server's list.
['/api/repos/:id'; delete]
fn (mut app App) delete_repo(id int) web.Result {
	if !app.is_authorized() {
		return app.json(http.Status.unauthorized, new_response('Unauthorized.'))
	}

	/* mut repos := rlock app.git_mutex { */
	/* 	git.read_repos(app.conf.repos_file) or { */
	/* 		app.lerror('Failed to read repos file.') */

	/* 		return app.status(http.Status.internal_server_error) */
	/* 	} */
	/* } */

	/* if id !in repos { */
	/* 	return app.not_found() */
	/* } */

	/* repos.delete(id) */
	app.db.delete_git_repo(id)

/* 	lock app.git_mutex { */
/* 		git.write_repos(app.conf.repos_file, &repos) or { return app.server_error(500) } */
/* 	} */

	return app.json(http.Status.ok, new_response('Repo removed successfully.'))
}

// patch_repo updates a repo's data with the given query params.
['/api/repos/:id'; patch]
fn (mut app App) patch_repo(id string) web.Result {
	if !app.is_authorized() {
		return app.json(http.Status.unauthorized, new_response('Unauthorized.'))
	}

	mut repos := rlock app.git_mutex {
		git.read_repos(app.conf.repos_file) or {
			app.lerror('Failed to read repos file.')

			return app.status(http.Status.internal_server_error)
		}
	}

	if id !in repos {
		return app.not_found()
	}

	repos[id].patch_from_params(app.query)

	lock app.git_mutex {
		git.write_repos(app.conf.repos_file, &repos) or { return app.server_error(500) }
	}

	return app.json(http.Status.ok, new_response('Repo updated successfully.'))
}
