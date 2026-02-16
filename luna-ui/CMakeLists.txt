cmake_minimum_required(VERSION 3.16)
project(luna-ui VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Sql Network WebEngineQuick)
find_package(SDL2 REQUIRED)

# FIX #45: Register QML files with qt_add_qml_module
qt_add_executable(luna-ui
    src/main.cpp
    src/gamemanager.cpp
    src/database.cpp
    src/controllermanager.cpp
    src/thememanager.cpp
    src/artworkmanager.cpp
    src/storebackends/steambackend.cpp
    src/storebackends/heroicbackend.cpp
    src/storebackends/lutrisbackend.cpp
    src/storebackends/custombackend.cpp
    src/storeapimanager.cpp
)

qt_add_qml_module(luna-ui
    URI LunaUI
    RESOURCE_PREFIX /
    QML_FILES
        qml/Main.qml
        qml/views/GamesView.qml
        qml/views/StoreView.qml
        qml/views/MediaView.qml
        qml/views/SettingsView.qml
        qml/components/GameCard.qml
        qml/components/NavBar.qml
        qml/components/HeroSection.qml
        qml/components/SearchBar.qml
        qml/components/GameDetailView.qml
        qml/components/SteamSetupWizard.qml
        qml/components/GameStorePage.qml
        qml/components/StoreGameCard.qml
        qml/components/GameStoreDetailPopup.qml
)

target_link_libraries(luna-ui PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Sql
    Qt6::Network
    Qt6::WebEngineQuick
    SDL2::SDL2
)

install(TARGETS luna-ui DESTINATION /usr/bin)
install(DIRECTORY resources/themes DESTINATION /usr/share/luna-ui)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/resources/fonts")
    install(DIRECTORY resources/fonts DESTINATION /usr/share/luna-ui)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons")
    install(DIRECTORY resources/icons DESTINATION /usr/share/luna-ui)
endif()
