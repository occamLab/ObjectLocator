let functions = require('firebase-functions');
let admin = require('firebase-admin');
admin.initializeApp(functions.config().firebase);

exports.sendNotification = functions.database.ref('labeling_jobs/{jobUUID}')
    .onWrite(event => {
       console.log('I am a log message');
       console.log('received ' + event.params.jobUUID);


       const payload = {
         notification: {
	   title: 'New message by test',
           body: 'blah blah',
	   labeling_job_id: event.params.jobUUID,
	 }
       };
       // need to cache / update notification keys properly in database
       var tokenRef = admin.database().ref('notification_tokens')
       tokenRef.once("value", function(snapshot) {
	       snapshot.forEach(function(child) {
		       // TODO: are we fetching data twice??
		       var subRef = tokenRef.child(child.key);
		       subRef.once("value", function(snapshot2) {
		               snapshot2.forEach(function(child2) {
            		               admin.messaging().sendToDevice(child2.key, payload).then(function (response) {
                    				console.log("Successfully sent message:", response);
                		       }).catch(function (error) {
                    				console.log("Error sending message:", error);
                		       });
		       	       });
		       });
		});
      }); 
    });
