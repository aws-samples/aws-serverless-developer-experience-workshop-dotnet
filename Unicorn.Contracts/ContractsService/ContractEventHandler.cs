// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using Amazon.Lambda.Core;
using Amazon.Lambda.SQSEvents;
using Amazon.XRay.Recorder.Handlers.AwsSdk;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// 
/// </summary>
public class ContractEventHandler
{
    private readonly AmazonDynamoDBClient _dynamoDbClient;
    private readonly string? _dynamodbTable;

    /// <summary>
    /// Default constructor for ContractEventHandler
    /// </summary>
    public ContractEventHandler()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();

        // Initialise DDB Client 
        _dynamoDbClient = new AmazonDynamoDBClient();

        // Initialise DDB table name from Environment Variables
        _dynamodbTable = Environment.GetEnvironmentVariable("DYNAMODB_TABLE");
        if (string.IsNullOrEmpty(_dynamodbTable))
        {
            throw new Exception("Environment variable DYNAMODB_TABLE is not defined.");
        }
    }

    /// <summary>
    /// Testing constructor for ContractEventHandler
    /// </summary>
    /// <param name="dynamoDbClient">Amazon DynamoDB Client object</param>
    public ContractEventHandler(AmazonDynamoDBClient dynamoDbClient)
    {
        _dynamoDbClient = dynamoDbClient;
        _dynamodbTable = Environment.GetEnvironmentVariable("DYNAMODB_TABLE") ?? string.Empty;
    }

    /// <summary>
    /// Lambda Handler for creating new Contracts.
    /// </summary>
    /// <param name="sqsEvent">AWS SQS record. Could contain batch of records.</param>
    /// <param name="context">The context for the Lambda function.</param>
    /// <returns>API Gateway Lambda Proxy Response.</returns>
    public async Task FunctionHandler(SQSEvent sqsEvent, ILambdaContext context)
    {
        // Multiple records can be delivered in a single event
        Console.WriteLine($"Beginning to process {sqsEvent.Records.Count} records...");

        foreach (var record in sqsEvent.Records)
        {
            var method = record.MessageAttributes["HttpMethod"].StringValue; //?? "No attribute with HttpMethod";
            Console.WriteLine($"Identified HTTP Method : {method}");

            switch (method)
            {
                case "POST":
                    await CreateContractAsync(record);
                    break;
                case "PUT":
                    await UpdateContractAsync(record);
                    break;
                default:
                    Console.WriteLine("Nothing to process.");
                    break;
            }
        }

        Console.WriteLine("Processing complete.");
    }

    /// <summary>
    /// Create contract inside DynamoDB table
    /// Execution logic:
    ///  if contract does not exist
    ///  or contract status is either of [ CANCELLED | CLOSED | EXPIRED]
    ///  then create or replace contract with status = DRAFT
    ///  else
    ///  log exception message
    /// </summary>
    /// <param name="sqsMessage"></param>
    private async Task CreateContractAsync(SQSEvent.SQSMessage sqsMessage)
    {
        throw new NotImplementedException();
    }
    
    private async Task UpdateContractAsync(SQSEvent.SQSMessage sqsMessage)
    {
        throw new NotImplementedException();
    }
}