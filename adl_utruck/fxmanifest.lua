fx_version 'cerulean'
game 'gta5'
use_experimental_fxv2_oal 'yes'
lua54 'yes'


files {
    "data/*.meta",
    "ui/index.html",
    "ui/style.css",
    "ui/app.js",
    "ui/assets/*.png",
}

ui_page "ui/index.html"

shared_scripts {
    '@ox_lib/init.lua',
}

data_file "VEHICLE_METADATA_FILE" "data/vehicles.meta"
data_file "CARCOLS_FILE" "data/carcols.meta"
data_file "VEHICLE_VARIATION_FILE" "data/carvariations.meta"

client_script "truck_client.lua"
server_script "truck_server.lua"
