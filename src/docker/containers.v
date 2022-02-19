module docker

import json
import net.urllib

struct Container {
	id    string
	names []string
}

pub fn containers() ?[]Container {
	res := get(urllib.parse('/containers/json') ?) ?

	return json.decode([]Container, res.text) or {}
}
