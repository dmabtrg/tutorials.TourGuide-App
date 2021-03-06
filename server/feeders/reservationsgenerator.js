/*
 * reservations_generator.js
 * Copyright(c) 2015 Bitergia
 * Author: Alvaro del Castillo <acs@bitergia.com>,
 * Alberto Martín <amartin@bitergia.com>
 * MIT Licensed

  Generates random reservations for restaurants in orion

  First it gets all restaurant information
  Then a random automatic reservation is generated
  Then the reservation is added to Orion CB

*/

// jshint node: true

'use strict';

var utils = require('../utils');
var async = require('async');
var shortid = require('shortid'); // unique ids generator
var apiRestSimtasks = 5; // number of simultaneous calls to API REST
var reservationsAdded = 0;
var restaurantsData; // All data for the restaurants to be reserved

var config = require('../config');
var fiwareHeaders = {
  'fiware-service': config.fiwareService
};

var feedOrionReservations = function() {
  var returnPost = function(data) {
    reservationsAdded++;
    console.log(reservationsAdded + '/' + restaurantsData.length);
  };

  // restaurantsData = restaurantsData.slice(0,5); // debug with few items

  console.log('Feeding reservations info in orion.');
  console.log('Number of restaurants: ' + restaurantsData.length);

  // Limit the number of calls to be done in parallel to orion
  var q = async.queue(function(task, callback) {
    var attributes = task.attributes;

    utils.sendRequest('POST', attributes, null, fiwareHeaders)
    .then(callback)
    .catch(function(err) {
      console.log(err);
    });
  }, apiRestSimtasks);

  q.drain = function() {
    console.log('Total reservations added: ' + reservationsAdded);
  };

  Object.keys(restaurantsData).forEach(function(element, pos) {
    // Call orion to append the entity
    var restaurantName = restaurantsData[pos].id + '-' + shortid.generate();

    var reservations = ['Cancelled', 'Confirmed', 'Hold', 'Pending'];

    var attr = {
      'type': 'FoodEstablishmentReservation',
      'id': restaurantName,
      'reservationStatus': utils.randomElement(reservations),
      'underName': {},
      'reservationFor': {},
      'startTime': utils.getRandomDate().getTime(),
      'partySize': utils.randomIntInc(1, 20)
    };

    // Time to add first attribute to orion as first approach
    attr.underName.type = 'Person';
    attr.underName.name = 'user' + utils.randomIntInc(1, 10);

    attr.reservationFor.type = 'FoodEstablishment';
    attr.reservationFor.name = restaurantsData[pos].id;
    attr.reservationFor.address = restaurantsData[pos].address;

    q.push({
      'attributes': attr
    }, returnPost);
  });
};

// Load restaurant data from Orion
var loadRestaurantData = function() {

  // Once we have all data for restaurants generate reviews for them

  var processRestaurants = function(data) {
    restaurantsData = JSON.parse(JSON.stringify(data.body));
    feedOrionReservations();
  };
  utils.getListByType('Restaurant',null,fiwareHeaders)
  .then(processRestaurants)
  .catch(function(err) {
    console.log(err);
  });
};

console.log('Generating random reservations for restaurants ...');

loadRestaurantData();
