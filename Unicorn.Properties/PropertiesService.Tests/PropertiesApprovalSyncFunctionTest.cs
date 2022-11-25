using System;
using System.Threading;
using System.Threading.Tasks;
using Amazon.DynamoDBv2.DataModel;
using Amazon.StepFunctions;
using Amazon.StepFunctions.Model;
using Moq;
using Xunit;
using Xunit.Abstractions;

namespace Unicorn.Properties.PropertiesService.Tests
{
    public class PropertiesApprovalSyncFunctionTest
    {
        private readonly ITestOutputHelper _testOutputHelper;
        private const string Token = "AQDIAAAAKgAAAAMAAAAAAAAAAapnwdMR3Z7RAg3IavSq2hbHt+CZPIQYaakFO6Em9Ik00VsGcaznxo" +
                                     "tIUGB2t7kihvuu/ffeoF+Z4yg4dggTxtzVwvRJwUDQr33/s/LhJyvEfNS57PXCv/CYFssJZ+28FRCAYb" +
                                     "GekKaopYhaUlvq0taLGMaEfIbRBeLUmLHInDkPPDbwTA==N0LRrCP3bIFW1MPkMQC3kd35p8yflvpThH" +
                                     "Ceviqe3qeyKBX03+ziocuyvNHVpktMuECnHL3MN9a6BfpSM1KItYI+qdIC74ls83ALSjjOs8G8pOz4Ou" +
                                     "dcliLYAvmZPRQXvFaw6aSMLfJJ7xRpEFSBwj1zDzbadMLtfudG78pmZX1m75/idMU5gz0UPkC87bVQN6" +
                                     "Kyjl7obxAeUO4aoqGJeNz6WbJQtrsUhiQWVEH/AwjUAj9Q0DwRqRPqeWyrv4MIMKea/Xu9vhXbcS+zPWP" +
                                     "q8onN9fyAqoMNh64K6wSGWxtAbaaByKxNpQu7o9ho/Iu/ME0KOAqyUK6vcnXOpIwIoMAZiG34KF4UnQsD0" +
                                     "gIokQcGLbehMGRixvEJMDZIloLxkuH0jvpIvD5xokGxpHwiVMISi2XRJ92nnGmWTCLWqsqJlsg4We6snJp" +
                                     "0Akw2w1Nt41lgY8kWkjxHNWEHDIMjzx1zeWiVa9b9aDDcckb71ouknJCN4gbxVs+yP30M97qnCEmMrc25" +
                                     "Yq7cEXLhu5Dh";

        public PropertiesApprovalSyncFunctionTest(ITestOutputHelper testOutputHelper)
        {
            _testOutputHelper = testOutputHelper;
        }

        [Fact]                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  
        public void StatusIsDraftSyncShouldNotSendTaskSuccess()
        {
            // Setup
            var ddbEvent = TestHelpers.LoadDynamoDbEventSource("./events/StreamEvents/contract_status_changed_draft.json");

            var retContractStatusItem = new ContractStatusItem
            {
                PropertyId = "usa/anytown/main-street/999",
                ContractId = Guid.NewGuid(),
                ContractStatus = "DRAFT",
                ContractLastModifiedOn = DateTime.Today,
                SfnWaitApprovedTaskToken = null
            };
            
            var mockDynamoDbContext = new Mock<IDynamoDBContext>();
            
            mockDynamoDbContext
                .Setup(x => x.LoadAsync<ContractStatusItem>(It.IsAny<string>(), CancellationToken.None).Result)
                .Returns(retContractStatusItem);
            
            var mockStepFunctionsClient = new Mock<AmazonStepFunctionsClient>();

            var context = TestHelpers.NewLambdaContext();

            var function =
                new PropertiesApprovalSyncFunction(mockStepFunctionsClient.Object, mockDynamoDbContext.Object);

            function.FunctionHandler(ddbEvent, context);

            mockStepFunctionsClient.Verify(
                client => client.SendTaskSuccessAsync(It.IsAny<SendTaskSuccessRequest>(),
                    It.IsAny<CancellationToken>()), Times.Never);
            
        }


        [Fact]
        public Task StatusIsApprovedNoTokenSyncShouldNotSendTaskSuccess()
        {
            var ddbEvent = TestHelpers.LoadDynamoDbEventSource("./events/StreamEvents/contract_status_changed_approved.json");

            var retContractStatusItem = new ContractStatusItem
            {
                PropertyId = "usa/anytown/main-street/999",
                ContractId = Guid.NewGuid(),
                ContractStatus = "APPROVED",
                ContractLastModifiedOn = DateTime.Today,
                SfnWaitApprovedTaskToken = null
            };
            
            var mockDynamoDbContext = new Mock<IDynamoDBContext>();
            mockDynamoDbContext
                .Setup(x => x.LoadAsync<ContractStatusItem>(It.IsAny<string>(), CancellationToken.None).Result)
                .Returns(retContractStatusItem);
            
            var mockStepFunctionsClient = new Mock<AmazonStepFunctionsClient>();

            var context = TestHelpers.NewLambdaContext();

            var function =
                new PropertiesApprovalSyncFunction(mockStepFunctionsClient.Object, mockDynamoDbContext.Object);

            function.FunctionHandler(ddbEvent, context);

            mockStepFunctionsClient.Verify(
                client => client.SendTaskSuccessAsync(It.IsAny<SendTaskSuccessRequest>(),
                    It.IsAny<CancellationToken>()), Times.Never);

            return Task.CompletedTask;
        }


        [Fact]
        public Task StatusIsDraftWithTokenSyncShouldNotSendTaskSuccess()
        {
            var ddbEvent = TestHelpers.LoadDynamoDbEventSource("./events/StreamEvents/contract_status_draft_waiting_for_approval.json");

            var retContractStatusItem = new ContractStatusItem
            {
                PropertyId = "usa/anytown/main-street/999",
                ContractId = Guid.NewGuid(),
                ContractStatus = "DRAFT",
                ContractLastModifiedOn = DateTime.Today,
                SfnWaitApprovedTaskToken = Token
            };
            
            var mockDynamoDbContext = new Mock<IDynamoDBContext>();
            mockDynamoDbContext
                .Setup(x => x.LoadAsync<ContractStatusItem>(It.IsAny<string>(), CancellationToken.None).Result)
                .Returns(retContractStatusItem);
            
            var mockStepFunctionsClient = new Mock<AmazonStepFunctionsClient>();

            var context = TestHelpers.NewLambdaContext();

            var function =
                new PropertiesApprovalSyncFunction(mockStepFunctionsClient.Object, mockDynamoDbContext.Object);

            function.FunctionHandler(ddbEvent, context);

            mockStepFunctionsClient.Verify(
                client => client.SendTaskSuccessAsync(It.IsAny<SendTaskSuccessRequest>(),
                    It.IsAny<CancellationToken>()), Times.Never);

            return Task.CompletedTask;
        }
        
        
        [Fact]
        public Task StatusIsApprovedWithTokenSyncShouldSendTaskSuccess()
        {
            var ddbEvent = TestHelpers.LoadDynamoDbEventSource("./events/StreamEvents/contract_status_changed_approved_waiting_for_approval.json");
            
            var retContractStatusItem = new ContractStatusItem
            {
                PropertyId = "usa/anytown/main-street/999",
                ContractId = Guid.NewGuid(),
                ContractStatus = "APPROVED",
                ContractLastModifiedOn = DateTime.Today,
                SfnWaitApprovedTaskToken = Token
            };
            
            var mockDynamoDbContext = new Mock<IDynamoDBContext>();
            mockDynamoDbContext
                .Setup(x => x.LoadAsync<ContractStatusItem>(It.IsAny<string>(), CancellationToken.None).Result)
                .Returns(retContractStatusItem);
            
            var mockStepFunctionsClient = new Mock<AmazonStepFunctionsClient>();

            var context = TestHelpers.NewLambdaContext();

            var function =
                new PropertiesApprovalSyncFunction(mockStepFunctionsClient.Object, mockDynamoDbContext.Object);

            function.FunctionHandler(ddbEvent, context);

            mockStepFunctionsClient.Verify(
                client => client.SendTaskSuccessAsync(It.IsAny<SendTaskSuccessRequest>(),
                    It.IsAny<CancellationToken>()), Times.Once);

            return Task.CompletedTask;
        }
    }
}