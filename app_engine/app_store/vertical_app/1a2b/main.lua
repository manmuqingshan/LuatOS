PROJECT = "1A2B_GAME"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- exwin = require "exwin"
require "1a2b_win"

sys.publish("OPEN_1A2B_WIN")

sys.run()
