let functions = require('firebase-functions');
let admin = require('firebase-admin');

admin.initializeApp(functions.config().firebase);

const keyFilename="./keys/object-locator-firebase-adminsdk-on2et-4496cc5626.json";
const projectId = "object-locator" //replace with your project id
const bucketName = `${projectId}.appspot.com`;

const gcs = require('@google-cloud/storage')({
	    projectId,
	    keyFilename
});

const bucket = gcs.bucket(bucketName);

// this is just an arbitrary trigger
exports.cleanupOldDataCron = functions.pubsub.topic('hourly-tick').onPublish((event) => {
     admin.database().ref('labeling_jobs').orderByChild('creation_timestamp').endAt((new Date).getTime()-120*1000).once('value').then(function(snapshot) {
	   snapshot.forEach(function(child) {
	    	var subRef = admin.database().ref('labeling_jobs/' + child.key + '/assignmentPaths').once('value').then(function(childSnapshot) {
	   		childSnapshot.forEach(function(subChild) {
				// TODO: this could be more efficiently done in batch
				admin.database().ref(subChild.val()).remove().catch(function(error) {})
			});
			bucket.file(child.key + '.jpg').delete().catch(function(error) {})
			admin.database().ref('responses/' + child.key).remove().catch(function(error) {})
			admin.database().ref('labeling_jobs/' + child.key).remove().catch(function(error) {})
		});
	   });
     }); 
});

exports.sendNotification = functions.database.ref('labeling_jobs/{jobUUID}')
    .onCreate(event => {
       console.log('received ' + event.params.jobUUID);

       const payload = {
         notification: {
	   title: 'Please help someone out.',
           body: 'Please find the requested object in the image.',
	   sound : 'default',
	   labeling_job_id: event.params.jobUUID,
	 }
       };
       // need to cache / update notification keys properly in database
       var tokenRef = admin.database().ref('notification_tokens')
       // TODOs:
       //   -it would be great to add some randomness (e.g., skip half the users)
       //   -we need to skip the users that have no notification tokens (most
	//	likely these are users of the ObjectLocator
	// set keeps track of the devices we've notified already.  This
	// prevents the same app instance from getting notified multiple
	// times if the user has signed in with more than one account.
       let notifiedTokens = new Set();
       let assignmentPaths = new Array();
       tokenRef.orderByChild("priority").limitToFirst(50).once('value').then(function(snapshot) {
	    snapshot.forEach(function(child) {
		var subRef = tokenRef.child(child.key);
		var addedAssignment = false;
		subRef.update({'priority': -((new Date).getTime())})
		subRef.once("value", function(snapshot2) {
		    snapshot2.forEach(function(child2) {
			if (child2.key != "priority" && child2.key != "assignments" && !notifiedTokens.has(child2.key)) {
			    notifiedTokens.add(child2.key)
			    admin.messaging().sendToDevice(child2.key, payload).then(function (response) {
				if (!addedAssignment) {
				    // TODO: write all assignments to the labeling_jobs/jobUUID as a list of references
				    subRef.child("assignments").update({[event.params.jobUUID]: {"object_to_find": event.data.val()["object_to_find"], "creation_timestamp": event.data.val()["creation_timestamp"]}})
				    assignmentPaths.push("notification_tokens/" + child.key + "/assignments/" + event.params.jobUUID)
				    addedAssignment = true;
				    // TODO: this is bad since it writes multiple times, could do this in batch
				    admin.database().ref('labeling_jobs/' + event.params.jobUUID).update({'assignmentPaths': assignmentPaths})
				}
			    }).catch(function (error) {
				console.log("Error sending message:", error);
			    });
			}
		    });
		});
	    });
       });
    });


exports.addPriority = functions.auth.user().onCreate(event => {
       console.log("user created", event);
       var priorityRef = admin.database().ref('notification_tokens/' + event.data.uid)
       priorityRef.update({'priority': 0})
});

// TODO: probably want to remove the notification tokens when user is deleted
