PROJECT = "DEPOSIT_CABINET"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

require "ecabinet"
require "ecboxstatus"
require "ecsend"
require "ecrecv"
require "eccourier"
require "eccourier_detail"
require "echelp"

sys.publish("OPEN_EXPRESS_CABINET_WIN")

sys.run()
