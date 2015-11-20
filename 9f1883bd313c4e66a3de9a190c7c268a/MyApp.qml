//------------------------------------------------------------------------------

import QtQuick 2.3
import QtQuick.Controls 1.2
import QtQuick.Layouts 1.1
import QtPositioning 5.3

import ArcGIS.AppFramework 1.0
import ArcGIS.AppFramework.Controls 1.0
import ArcGIS.AppFramework.Runtime 1.0
import ArcGIS.AppFramework.Runtime.Controls 1.0
import ArcGIS.AppFramework.Runtime.Dialogs 1.0



import "Helper.js" as Helper

App {
    id: app
    width: 300
    height: 500

    UserCredentials {
        id: userCredentials
        userName: myUsername
        password: myPassword

        onError: console.log("ERROR")
        onTokenChanged: console.log("token changed")
        //onAuthenticatingHostChanged: consolelog("AuthenticatingHostChanged")
        onPasswordChanged: console.log("PasswordChanged")
        //onTypeChanged: console.log("TypeChanged")
    }

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
//BEGIN INITIALIZING SOME GLOBAL VARIABLES USED FOR VARIOUS ODDS AND ENDS

    //define variables to hold the username and password
    property string myUsername: ""
    property string myPassword: ""

    //define global variable to hold last update date of tpk. Tried but did not manage to avoid this.
    property string tpkfilepath: ""

    //define global variable to hold the currently selected building, by ObjectID
    property var currentBuildingObjectID: ""
    //define global variable to hold the currently selected building id. used for communication between Helper functions
    property var currentBuildingID: ""

    //define global variable to hold list of buildings for search menu
    property var allBlgdList: []

    //define relevant field names. Ultimately these should all be configurable.
    property string bldgLyr_nameField: "NAME"
    property string bldgLyr_bldgIdField: "BUILDING_NUMBER"

    property string lineLyr_bldgIdField: "BUILDING"
    property string lineLyr_floorIdField: "FLOOR"
    property string lineLyr_sortField: "OBJECTID"

    property string roomLyr_bldgIdField: "BUILDING"
    property string roomLyr_floorIdField: "FLOOR"
    property string roomLyr_roomIdField: "ROOM"

//END INITIALIZING SOME GLOBAL VARIABLES USED FOR VARIOUS ODDS AND ENDS
//--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
//BEGIN DOWNOAD AND SYNC MECHANISM SETUP

    //Define place to store local geodatabase and declare FileInfo object.
    //Set up components for generate and sync functionality
    property string appItemId: app.info.itemId
    property string gdbPath: "~/ArcGIS/AppStudio/Data/" + appItemId + "/gdb.geodatabase"
    property string syncLogFolderPath: "~/ArcGIS/AppStudio/Data/" + appItemId
    property string updatesCheckfilePath: "~/ArcGIS/AppStudio/Data/" + appItemId + "/syncLog.txt"
    property string featuresUrl: "http://services.arcgis.com/8df8p0NlLFEShl0r/arcgis/rest/services/UMNTCCampusMini4/FeatureServer"
    FileInfo {
        id: gdbfile
        filePath: gdbPath

        function generategdb(){
            generateGeodatabaseParameters.initialize(serviceInfoTask.featureServiceInfo);
            generateGeodatabaseParameters.extent = map.extent;
            generateGeodatabaseParameters.returnAttachments = false;
            geodatabaseSyncTask.generateGeodatabase(generateGeodatabaseParameters, gdbPath);
        }
        function syncgdb(){
            gdb.path = gdbPath //if this is not set then function fails with "QFileInfo::absolutePath: Constructed with empty filename" message.
            gdbinfobuttontext.text = " Downloading updates now...this may take some time. "
            geodatabaseSyncTask.syncGeodatabase(gdb.syncGeodatabaseParameters, gdb);
        }
    }

    //use this file to keep track of when the app has synced last
    FileInfo {
        id: updatesCheckfile
        filePath: updatesCheckfilePath
    }
    FileFolder{
        id:syncLogFolder
        path: syncLogFolderPath
    }

    ServiceInfoTask{
        id: serviceInfoTask
        url: featuresUrl

        credentials: userCredentials

        onFeatureServiceInfoStatusChanged: {
            if (featureServiceInfoStatus === Enums.FeatureServiceInfoStatusCompleted) {
                Helper.doorkeeper()
                userNameField.visible = false
                passwordField.visible = false
                signInButton.text = "Signed in as " + myUsername
                signInButton.anchors.top = signInDialogContainer.verticalCenter
                signInButton.enabled = false
                gdbinfocontainer.border.color = "white"
                gdbinfocontainer.border.width = 1
                gdbinfocontainer.update()
            } else if (featureServiceInfoStatus === Enums.FeatureServiceInfoStatusErrored) {
                Helper.preventGDBSync()
            }
        }
    }

    GenerateGeodatabaseParameters {
        id: generateGeodatabaseParameters
    }

    GeodatabaseSyncStatusInfo {
        id: syncStatusInfo
    }

    GeodatabaseSyncTask {
        id: geodatabaseSyncTask
        url: featuresUrl


        onGenerateStatusChanged: {
            if (generateStatus === Enums.GenerateStatusInProgress) {
                gdbinfobuttontext.text = " Downloading updates in progress...this may take some time. "
            } else if (generateStatus === Enums.GenerateStatusCompleted) {
                gdbfile.syncgdb();//a workaround. can only get layers to shown up in map after sync. not after initial generate.
            } else if (generateStatus === GeodatabaseSyncTask.GenerateError) {
                gdbinfobuttontext.text = "Error: " + generateGeodatabaseError.message + " Code= "  + generateGeodatabaseError.code.toString() + " "  + generateGeodatabaseError.details;
            }
        }

        onSyncStatusChanged: {
            if (syncStatus === Enums.SyncStatusCompleted) {
                Helper.writeSyncLog()
                Helper.doorkeeper()
            }
            if (syncStatus === Enums.SyncStatusErrored)
                gdbinfobuttontext.text = "Error: " + syncGeodatabaseError.message + " Code= "  + syncGeodatabaseError.code.toString() + " "  + syncGeodatabaseError.details;
        }
    }

    //set up components for operational map layers: buildings, room-polygons, lines
    Geodatabase{
        id: gdb
        path: gdbPath
    }

    GeodatabaseFeatureTable {
        id: localLinesTable
        geodatabase: gdb.valid ? gdb : null
        featureServiceLayerId: 0
        onQueryFeaturesStatusChanged: {
            console.log("onQueryFeaturesStatusChanged localLinesTable")
            if (queryFeaturesStatus === Enums.QueryFeaturesStatusCompleted) {
                Helper.populateFloorListView(queryFeaturesResult.iterator, currentBuildingID , lineLyr_sortField)
            }
        }
    }

    GeodatabaseFeatureTable {
        id: localRoomsTable
        geodatabase: gdb.valid ? gdb : null
        featureServiceLayerId: 1
    }

    GeodatabaseFeatureTable {
        id: localBuildingsTable
        geodatabase: gdb.valid ? gdb : null
        featureServiceLayerId: 2
        onQueryFeaturesStatusChanged: {
            if (queryFeaturesStatus === Enums.QueryFeaturesStatusCompleted) {
                Helper.buildAllBlgdList(queryFeaturesResult.iterator)
                console.log("Helper.buildAllBlgdList(queryFeaturesResult.iterator)")
                }
        }
    }

    //define place to store local tile package and define FileFolder object
    property string tpkItemId : "0ae5d71749504e9784ac0d69ea27110f"
    FileFolder {
        id: tpkFolder
        path: "~/ArcGIS/AppStudio/Data/" + tpkItemId

        function addLayer(){
            var filesList = tpkFolder.fileNames("*.tpk");
            var newLayer = ArcGISRuntime.createObject("ArcGISLocalTiledLayer");
            var newFilePath = tpkFolder.path + "/" + filesList[0];
            newLayer.path = newFilePath;
            tpkfilepath = newFilePath;
            map.insertLayer(newLayer,0);//insert it at the bottom of the layer stack
            map.addLayer(newLayer)
            map.extent = newLayer.extent
        }

        function downloadThenAddLayer(){
            map.removeLayerByIndex(0)
            downloadTpk.download(tpkItemId);
        }
    }
    //instantiate FileInfo to read last modified date of tpk.
    FileInfo{
        id:tpkfile
        filePath: tpkfilepath
    }



    //Declare ItemPackage for downloading tile package
    ItemPackage {
        id: downloadTpk
        onDownloadStarted: {
            console.log("Download started")
            tpkinfobuttontext.text = "Download starting... 0%"
        }
        onDownloadProgress: {
            tpkinfobuttontext.text = "Download in progress... " + percentage +"%"
        }
        onDownloadComplete: {
            tpkFolder.addLayer();
            Helper.doorkeeper();
        }
        onDownloadError: {
            tpkinfobuttontext.text = "Download failed"
        }
    }

//END DOWNLOAD AND SYNC MECHANISM SETUP
//--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

//--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
//BEGIN MAP AND ON-MAP COMPONENTS

    Rectangle{
        id:topbar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width:parent.width
        height: zoomButtons.width * 1.4
        color: "darkblue"

        StyleButton{
            id: welcomemenu
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height:parent.height * 0.9
            anchors.leftMargin: 2
            width:height
            iconSource: "images/actions.png"
            onClicked: {
                console.log("click")
                //destory and re-fetch this info to ensure device connectiviy and feature service avaiability before allowing user to kick-off sync opeation
                //serviceInfoTask.featureServiceInfo.destroy()//test whetehr ths idea works
                //serviceInfoTask.fetchFeatureServiceInfo()//this is a bit buggy in that it takes a while to fail. Maybe re-design rocess to by default prevent sync until readiness is verified
                proceedtomaptext.text  = "Back to Map"
                welcomemenucontainer.visible = true
                Helper.doorkeeper()
            }
        }
        Text{
            id:titletext
            text:"Floor Plan Viewer"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            height:parent.height
            width: parent.width - height * 2
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            font.pixelSize: 72
            clip:true
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment:  Text.AlignHCenter
            color:"white"
            font.weight: Font.DemiBold
        }

        StyleButton{
            id: searchmenu
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height:parent.height * 0.9
            anchors.rightMargin: 2
            width:height
            iconSource: "images/search.png"
            onClicked: {
                console.log("click searchmenu")
                if (searchmenucontainer.visible === true){
                    searchmenucontainer.visible = false
                } else{
                    Helper.reloadFullBldgListModel()
                    searchmenucontainer.visible = true
                }
            }
        }
    }

    Rectangle{
        id:mapcontainer
        height: parent.height - topbar.height
        width: parent.width
        anchors.top: topbar.bottom


        Map{
            id: map
            anchors.top: parent.top
            anchors.bottom: mapcontainer.bottom
            anchors.left: mapcontainer.left
            anchors.right: mapcontainer.right
            focus: true
            rotationByPinchingEnabled: true
            positionDisplay {
                positionSource: PositionSource {
                }
            }

            StyleButton {
                id: infobutton
                iconSource: "images/info1.png"
                width: zoomButtons.width
                height: width
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: app.height * 0.01
                anchors.bottomMargin: 2
                onClicked: {
                    fader.start();
                    console.log("infobutton")
                    infocontainer.visible = true
                    infotext.text = "Select a building via the map or the search menu."
                }
            }
            ZoomButtons {
                id:zoomButtons
                anchors.left: parent.left
                anchors.bottom: infobutton.top
                anchors.margins: app.height * 0.01
            }
            StyleButton {
                id: buttonRotateCounterClockwise
                iconSource: "images/rotate_clockwise.png"
                width: zoomButtons.width
                height: width
                anchors.bottom: zoomButtons.top
                anchors.left: zoomButtons.left
                anchors.bottomMargin: 2
                onClicked: {
                    fader.start();
                    map.mapRotation -= 22.5;
                }
            }
            StyleButton{
                id: northarrowbackgroundbutton
                anchors {
                    right: buttonRotateCounterClockwise.right
                    bottom: buttonRotateCounterClockwise.top
                }
                visible: map.mapRotation != 0
            }
            NorthArrow{
                width: northarrowbackgroundbutton.width - 4
                height: northarrowbackgroundbutton.height - 4

                anchors {
                    horizontalCenter: northarrowbackgroundbutton.horizontalCenter
                    verticalCenter: northarrowbackgroundbutton.verticalCenter
                }
                visible: map.mapRotation != 0
            }

            Rectangle{
                id:floorcontainer
                width: zoomButtons.width
                anchors.bottom: zoomButtons.bottom
                anchors.right: map.right
                anchors.margins: app.height * 0.01
                height: ((floorListView.count * width) > (mapcontainer.height - zoomButtons.width)) ? (mapcontainer.height - zoomButtons.width)  :  (floorListView.count * width)
                color: zoomButtons.borderColor
                border.color: zoomButtons.borderColor
                border.width: zoomButtons.borderWidth
                visible: false

                ListView{
                    id:floorListView
                    anchors.fill: parent
                    model:floorListModel
                    delegate:floorListDelegate
                    verticalLayoutDirection : ListView.BottomToTop
                    highlight:
                        Rectangle {
                                color: "transparent";
                                radius: 4;
                               border.color: "blue";
                                border.width: 5;
                                z : 98;}
                    focus: true
                    clip:true
                    visible: parent
                }

                ListModel {
                    id:floorListModel
                    ListElement {
                        Floor: ""
                    }
                }
                Component {
                    id: floorListDelegate
                    Item {
                        width: zoomButtons.width
                        height: width
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle{
                            anchors.fill:parent
                            border.color: zoomButtons.borderColor
                            color:zoomButtons.backgroundColor
                            anchors.margins: 1
                        }

                        Column {
                            Text { text: Floor}
                            anchors.centerIn:parent

                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                floorListView.currentIndex = index;
                                Helper.setFloorFilters(index);
                                    }
                        }
                    }
                }

            }

            Rectangle{
               id:infocontainer
               height: infobutton.height
               anchors.left: infobutton.left
               anchors.right: parent.right
               anchors.top: infobutton.top
               anchors.rightMargin: app.height * 0.01
               color: infobutton.backgroundColor
               border.color: infobutton.borderColor
               radius: 4
               clip: true


               Row{
                   id:inforow
                   height: parent.height - 2
                   width: parent.width - 2
                   anchors.horizontalCenter: parent.horizontalCenter
                   anchors.verticalCenter: parent.verticalCenter
                   spacing: 2

                   StyleButton{
                       id:closeinfobutton
                       height:parent.height
                       width: height
                       iconSource: "images/close.png"
                       borderColor: infobutton.backgroundColor
                       focusBorderColor: infobutton.backgroundColor
                       hoveredColor: infobutton.backgroundColor
                       anchors.verticalCenter: parent.verticalCenter
                       onClicked: {
                           console.log("click")
                           infocontainer.visible = false
                           floorcontainer.visible = false
                           currentBuildingObjectID = ""
                           currentBuildingID = ""
                           localBuildingsLayer.clearSelection();
                           Helper.hideAllFloors();
                       }
                   }
                   Text{
                       id:infotext
                       text: "Some text messages displayed here."
                       color: "black"
                       wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                       fontSizeMode: Text.Fit
                       minimumPixelSize: 12
                       font.pixelSize: 14
                       clip:true
                       width:infocontainer.width - closeinfobutton.width - zoomtoinfobutton.width - 4
                       anchors.verticalCenter: parent.verticalCenter
                   }
                   StyleButton{
                       id:zoomtoinfobutton
                       height:parent.height
                       width: height
                       iconSource: "images/signIn.png"
                       borderColor: infobutton.backgroundColor
                       focusBorderColor: infobutton.backgroundColor
                       hoveredColor: infobutton.backgroundColor
                       anchors.verticalCenter: parent.verticalCenter
                       onClicked: {
                           console.log("click")
                           console.log(currentBuildingObjectID)
                           map.zoomTo(localBuildingsLayer.featureTable.feature(currentBuildingObjectID).geometry)
                       }
                   }

               }

            }



            FeatureLayer {
                id: localBuildingsLayer
                featureTable: localBuildingsTable
                selectionColor: "white"
            }
                onMouseClicked:{
                Helper.selectBuildingOnMap(mouse.x, mouse.y);
                }
            FeatureLayer {
                id: localRoomsLayer
                featureTable: localRoomsTable
                definitionExpression: "OBJECTID < 0"
            }
            FeatureLayer {
                id: localLinesLayer
                featureTable: localLinesTable
                definitionExpression: "OBJECTID < 0"
            }
        }

    }


//END MAP AND ON-MAP COMPONENTS
//--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
//BEGIN WELCOMEMENU
    Rectangle{
        id:welcomemenucontainer
        anchors.top: mapcontainer.top
        anchors.bottom: app.bottom
        anchors.right: app.right
        anchors.left: app.left
        border.width:1
        border.color: white

        Rectangle{
            id:titlecontainer
            height: welcomemenucontainer.height / 5
            width: welcomemenucontainer.width
            anchors.horizontalCenter:parent.horizontalCenter
            anchors.top: parent.top
            color:"darkblue"
            border.width:1
            border.color:"white"

            Text{
                id:appdescription
                anchors.top: apptitle.bottom
                width:parent.width
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                clip:true
                horizontalAlignment:Text.AlignHCenter
                color: "white"
                text: "\n"+"App Description Goes Here. App Description Goes Here. App Description Goes Here. App Description Goes Here."
            }
        }

        Rectangle{
            id:gdbinfocontainer
            height: welcomemenucontainer.height / 5
            width: welcomemenucontainer.width
            anchors.horizontalCenter:parent.horizontalCenter
            anchors.top: titlecontainer.bottom
            color:"darkblue"
            //border.width:1
            //border.color:"white"

            ImageButton{
                id: gdbinfoimagebutton
                source:"images/gallery-white.png"
                height: gdbinfocontainer.height / 1.5
                width: height
                anchors.top:gdbinfocontainer.top
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: {
                    console.log("click")
                    console.log("gdbfile.generategdb()")
                    if (gdbfile.exists){
                            gdbfile.syncgdb();
                            }
                    else {
                        gdbfile.generategdb();
                    }
                }
            }
            Text{
                id: gdbinfobuttontext
                anchors.top:gdbinfoimagebutton.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                color:"white"
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                width:parent.width
                clip:true
                horizontalAlignment:Text.AlignHCenter
            }
            MouseArea{
                anchors.fill: parent
                onClicked: {
                    console.log("click")
                    console.log("gdbfile.generategdb()")
                    if (gdbfile.exists){
                            gdbfile.syncgdb();
                            }
                    else {
                        gdbfile.generategdb();
                    }
                }
            }
        }
        Rectangle{
            id: signInDialogContainer
            height: welcomemenucontainer.height / 5
            width: welcomemenucontainer.width
            anchors.horizontalCenter:parent.horizontalCenter
            anchors.top: gdbinfocontainer.bottom
            color:"darkblue"
            //border.width:1
            //border.color:"white"
            visible:true
            TextField{
                    id: userNameField
                    width: parent.width
                    height:20
                    focus: true
                    visible: true
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 5
                    placeholderText :"ArcGIS Online Username"
            }
            TextField{
                    id: passwordField
                    width: parent.width
                    height:20
                    focus: true
                    visible: true
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: userNameField.bottom
                    anchors.margins: 5
                    placeholderText :"ArcGIS Online Password"
                    echoMode: TextInput.Password
                    }
            Button{
                id: signInButton
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: passwordField.bottom
                text: "Sign In"
                enabled: if (userNameField.length > 0 && passwordField.length > 0){true} else {false}
                onClicked: {console.log(userNameField.text);
                            console.log(passwordField.text);
                            myUsername = userNameField.text
                            myPassword = passwordField.text
                            userCredentials.userName = myUsername
                            userCredentials.password = myPassword
                            serviceInfoTask.fetchFeatureServiceInfo()
                            }
            }
        }

        Rectangle{
            id:tpkinfocontainer
            height: welcomemenucontainer.height / 5
            width: welcomemenucontainer.width
            anchors.horizontalCenter:parent.horizontalCenter
            anchors.top: signInDialogContainer.bottom
            color:"darkblue"
            border.width:1
            border.color:"white"

            ImageButton{
                id: tpkinfoimagebutton
                source:"images/gallery-white.png"
                height: tpkinfocontainer.height / 1.5
                width: height
                anchors.top:tpkinfocontainer.top
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: {
                    console.log("click")
                    tpkFolder.downloadThenAddLayer()

                }
            }
            Text{
                id: tpkinfobuttontext
                anchors.top:tpkinfoimagebutton.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                color:"white"
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                width:parent.width
                clip:true
                horizontalAlignment:Text.AlignHCenter
            }
            MouseArea{
                anchors.fill: parent
                onClicked: {
                    console.log("click middlebutton")
                    tpkFolder.removeFolder(tpkItemId, 1) //delete the tpk from local storage
                    tpkFolder.downloadThenAddLayer() //download and add the tpk layer
                }
            }

        }


        Rectangle{
            id:proceedbuttoncontainer
            height: welcomemenucontainer.height / 4
            width: welcomemenucontainer.width
            anchors.right:parent.right
            anchors.top: tpkinfocontainer.bottom
            color:"green"
            border.width:1
            border.color:"white"

            function proceedToMap(){
                console.log("proceedToMap")
                Helper.addAllLayers()
                welcomemenucontainer.visible = false
            }

            ImageButton{
                id: proceedtomapimagebutton
                source:"images/gallery-white.png"
                height: proceedbuttoncontainer.height / 1.5
                width: height
                anchors.top:proceedbuttoncontainer.top
                anchors.horizontalCenter: proceedbuttoncontainer.horizontalCenter
                onClicked: {
                    proceedbuttoncontainer.proceedToMap();
                }
            }

            Text{
                id:proceedtomaptext
                anchors.top:proceedtomapimagebutton.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                color:"white"
                text: "Go to Map"
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                width:parent.width
                clip:true
                horizontalAlignment:Text.AlignHCenter
            }

            MouseArea{
                id:proceedbuttoncontainermousearea
                anchors.fill: proceedbuttoncontainer
                onClicked: {
                    proceedbuttoncontainer.proceedToMap();
                }
            }
        }
    }
//END WELCOMENU
//---------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------
//BEGIN SEARCHMENU
    Rectangle{
        id:searchmenucontainer
        anchors.top: mapcontainer.top
        anchors.bottom: mapcontainer.bottom
        anchors.right: mapcontainer.right
        anchors.left: mapcontainer.left
        color: "white"
        visible:false

        TextField{
                id: searchField
                width: parent.width
                height:30
                focus: true
                visible: true
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 2
                placeholderText :"Building Name"
                onTextChanged: {
                    if(text.length > 0 ) {
                                Helper.reloadFilteredBldgListModel(text);
                            } else {
                                Helper.reloadFullBldgListModel();
                            }
                        }
        }
        ListView{
            id:bldglistview
            clip: true
            width: parent.width
            height: parent.height
            anchors.top: searchField.bottom
            model: bldglistmodel
            delegate: bldgdelegate
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
        }

        Component {
            id: bldgdelegate
            Item {
                width: parent.width
                height: searchField.height
                anchors.margins: 2
                anchors.left: parent.left
                Column {
                    Text { text: bldgname + ' (#' + bldgid + ')'}
                    Text { text: objectid ; visible: false}
                    anchors.left:parent.left
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        //this should be enhanced to auto-select the feature and zoom to envelope
                        map.zoomTo(localBuildingsLayer.featureTable.feature(objectid).geometry)
                        searchField.text = ""
                        searchmenucontainer.visible = false
                        Helper.updateBuildingDisplay(objectid)
                        }
                }
            }
        }
        ListModel{
            id:bldglistmodel
            ListElement {
                objectid : "objectid"
                bldgname: "bldgname"
                bldgid: "bldgid"
            }
        }


    }
//END SEARCHMENU
//---------------------------------------------------------------------------------------------

    Component.onCompleted: {
        Helper.getAllBldgs()
        Helper.addAllLayers()
        tpkFolder.addLayer()
        Helper.doorkeeper()
        serviceInfoTask.fetchFeatureServiceInfo();
        console.log(allBlgdList)
        console.log("app load complete")
        console.log(userCredentials.userName)
    }

}

