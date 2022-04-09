module cron

import cli
import env

struct Config {
pub:
	log_level    string = 'WARN'
	log_file     string = 'vieter.log'
	api_key      string
	address string
	base_image string = 'archlinux:base-devel'
}

pub fn cmd() cli.Command {
	return cli.Command{
		name: 'cron'
		description: 'Start the cron service that periodically runs builds.'
		execute: fn (cmd cli.Command) ? {
			config_file := cmd.flags.get_string('config-file') ?
			conf := env.load<Config>(config_file) ?

			cron(conf) ?
		}
	}
}
