// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.Core;
using Amazon.Util;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Tracing;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
//[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Unicorn.Properties.PropertiesService;

/// <summary>
/// Represents the AWS Lambda function that checks the existence of a contract in the Properties Service
/// contract Status table
/// </summary>
public class ContractExistsCheckerFunction
{
    private readonly IDynamoDBContext _dynamoDbContext;

    /// <summary>
    /// Default constructor. Initialises global variables for function.
    /// </summary>
    /// <exception cref="Exception">Init exception</exception>
    public ContractExistsCheckerFunction()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();

        var dynamodbTable = Environment.GetEnvironmentVariable("CONTRACT_STATUS_TABLE");
        if (string.IsNullOrEmpty(dynamodbTable))
        {
            throw new Exception("Environment variable CONTRACT_STATUS_TABLE is not defined.");
        }

        AWSConfigsDynamoDB.Context.TypeMappings[typeof(ContractStatusItem)] =
            new TypeMapping(typeof(ContractStatusItem), dynamodbTable);

        var config = new DynamoDBContextConfig { Conversion = DynamoDBEntryConversion.V2 };
        _dynamoDbContext = new DynamoDBContext(new AmazonDynamoDBClient(), config);
    }


    /// <summary>
    /// Event handler for ContractStatusChangedEvent
    /// </summary>
    /// <param name="input">The input payload</param>
    /// <param name="context">Lambda Context runtime methods and attributes</param>
    /// <exception cref="ContractStatusNotFoundException"></exception>
    [Logging(LogEvent = true)]
    [Tracing(CaptureMode = TracingCaptureMode.ResponseAndError)]
    public async Task FunctionHandler(object input, ILambdaContext context)
    {
        var document = JsonSerializer.SerializeToDocument(input);
        var propertyId = document.RootElement.GetProperty("Input").GetProperty("PropertyId").GetString();
        var item = await GetContractStatus(propertyId ?? "").ConfigureAwait(false);
        if (item == null)
        {
            throw new ContractStatusNotFoundException($"Could not find property with ID: {propertyId}");
        }
    }


    /// <summary>
    /// Retrieves the contract status for a specifies property
    /// </summary>
    /// <param name="propertyId">Property ID</param>
    /// <returns>Instance of <see cref="ContractStatusItem"/></returns>
    [Tracing]
    private async Task<ContractStatusItem?> GetContractStatus(string propertyId)
    {
        try
        {
            Logger.LogInformation($"Getting Contract Status for {propertyId}");
            var item = await _dynamoDbContext.LoadAsync<ContractStatusItem>(propertyId).ConfigureAwait(false);
            Logger.LogInformation($"Found contact: {item != null}");
            return item;
        }
        catch (Exception e)
        {
            Logger.LogInformation($"Error loading contract {propertyId}: {e.Message}");
            return null;
        }
    }
}