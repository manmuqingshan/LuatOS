PROJECT = "VENDING_MACHINE"
VERSION = "001.000.002"

log.info("main", PROJECT, VERSION)

require "vending_main_win"
require "inventory_win"

sys.publish("VENDING_MAIN_WIN")

sys.run()