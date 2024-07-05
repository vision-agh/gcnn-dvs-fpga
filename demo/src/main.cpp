#include <iostream>
#include "xgpiops.h"
#include "xparameters.h"
#include "platform.h"
#include <unistd.h>
#include "xscugic.h"
#include "ff.h"
#include "xtime_l.h"
#include "xil_io.h"
#define ZERO_POINT_IN 213 //165

XTime tEnd, tStart;
static FIL fil;
static FATFS fatfs;
const TCHAR *Path = "0:/";
char data_name[32] = "";
char data_name_weights[32] = "mw.txt";
char log_msg[256];
int log_msg_nChars;
int SDsetup(void);
int loadFile(u8 *dataPtr, char *FileName, int nBytes);

int ScuGicInterrupt_Init();
void InterruptHandler(void *data);
XScuGic InterruptController;
static XScuGic_Config *GicConfig;

char go;
char mnist_class;
char mnist_sample;
u32 data_in = 0;
int chars = 203078+700;//229184+2000;//203078+700;
char DestinationAddress[203078+700];//[229184+2000];//[203078+700];
u32 event_data[12279+50][4];//[14631][4];//[12279+50][4];
int charsW = 156712;//26700;
int weights_data[4096][10];
int features[4096];
int mod_cnt = 0;
bool done = 0;

int main()
{
    init_platform();
    std::cout << "--------------------------------------------------------------" << std::endl;
    std::cout << "Successfully initialised GCN application\n";

    int xstatus;
	xstatus = SDsetup();
	if (xstatus != XST_SUCCESS)
	{
		xil_printf("SD Card Setup Fail\r\n");
	}
	else
	{
		xil_printf("SD Card Setup Success\r\n");
	}

	xstatus = ScuGicInterrupt_Init();
	if (xstatus != XST_SUCCESS)
	{
		print("GIC Init Fail\r\n");
	}
	print("GIC Init Success\r\n");

	while(1)
	{
		int size = 12279+50;//14631;//12279+50;

		std::cout << "--------------------------------------------------------------" << std::endl;
		std::cout << "Input digit (0-9), otherwise quit: ";
		std::cin >> mnist_class;
		std::cout << mnist_class << std::endl;

		//NEW
		std::cout << "--------------------------------------------------------------" << std::endl;
		std::cout << "Input file number (0-9): ";
		std::cin >> mnist_sample;
		std::cout << mnist_sample << std::endl;

		if(int(mnist_class) >=48 && int(mnist_class) <= 57 && int(mnist_sample) >=48 && int(mnist_sample) <= 57)
		{
			std::string number = "";
			number.append("m");// = "m" + ".txt";// + std::__cxx11::to_string(go) + number[2];
			number.append(std::__cxx11::to_string(int(mnist_class)-48));
			number.append(std::__cxx11::to_string(int(mnist_sample)-48));
			number.append(".txt");

			strcpy(data_name, number.c_str());

			u8 dataPtr = 0;
			std::cout << "Reading events... ";// << std::endl;

			int data = loadFile(&dataPtr, data_name, chars);
			int counter = 0;

			char* token = strtok(DestinationAddress, " \n");
			while (token != NULL)
			{
				event_data[int(counter / 4)][int(counter % 4)] = std::__cxx11::stoi(token);
				counter = counter + 1;
				token = strtok(NULL, " \n");
			}
			std::cout << "done!" << std::endl;

			size = int(counter / 4);

			dataPtr = 0;
			std::cout << "Reading weights... ";// << std::endl;
			data = loadFile(&dataPtr, data_name_weights, charsW);
			counter = 0;

			char* tokenW = strtok(DestinationAddress, " \n");
			while (tokenW != NULL)
			{
				weights_data[int(counter / 10)][int(counter % 10)] = std::__cxx11::stoi(tokenW);
				counter = counter + 1;
				tokenW = strtok(NULL, " \n");
			}
			std::cout << "done!" << std::endl;

			unsigned int wait = 0;
			u32 timestamp = 0;
			u32 next_timestamp = 0;
			u32 x = 0;
			u32 y = 0;
			u32 polarity = 0;
			u32 valid = 0;
			u32 data_to_send1 = 0;
			u32 data_to_send2 = 0;

			XTime_GetTime(&tStart);
			for(int i = 0; i < size; i++)
			{
				timestamp = event_data[i][2];
				if(i < size - 1)
					next_timestamp = event_data[i+1][2];
				x = event_data[i][0];
				y = event_data[i][1];
				polarity = event_data[i][3];
				valid = 1;
				data_to_send1 = valid + 2*polarity + 4*y + 256*4*x;
				data_to_send2 = timestamp;
				Xil_Out32(XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR, data_to_send1);
				Xil_Out32(XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR, data_to_send2);
				wait = next_timestamp - timestamp;
				usleep(wait);
				if(timestamp > 200000)
					break;
			}
		}

		else
		{
			std::cout << "Exit!" << std::endl;
			cleanup_platform();
			return 0;
		}

		usleep(10000);
	}
}

int ScuGicInterrupt_Init()
{
	int Status;
	Xil_ExceptionInit();
	GicConfig = XScuGic_LookupConfig(XPAR_SCUGIC_0_DEVICE_ID);//XPAR_PS7_SCUGIC_0_DEVICE_ID);
	if (NULL == GicConfig)
	{
		return XST_FAILURE;
	}

	Status = XScuGic_CfgInitialize(&InterruptController, GicConfig,	GicConfig->CpuBaseAddress);
	if (Status != XST_SUCCESS)
	{
		return XST_FAILURE;
	}

	Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_IRQ_INT, (Xil_ExceptionHandler) XScuGic_InterruptHandler, (void *) &InterruptController);
	Status = XScuGic_Connect(&InterruptController, XPS_FPGA0_INT_ID, (Xil_ExceptionHandler)InterruptHandler, (void *)&InterruptController);
	XScuGic_Enable(&InterruptController, XPS_FPGA0_INT_ID);

	Xil_ExceptionEnable();
	XScuGic_SetPriorityTriggerType(&InterruptController, XPS_FPGA0_INT_ID, 0xa0, 3);

	if (Status != XST_SUCCESS)
	{
		return XST_FAILURE;
	}
	return XST_SUCCESS;
}

void InterruptHandler(void *data) {

	xil_printf("Feature vector %d received... ", mod_cnt+1);
    for(int i = 0; i < 1024; i++)
	{
		data_in = Xil_In32(XPAR_AXI_BRAM_CTRL_1_S_AXI_BASEADDR + 4*i);
		features[int((i/64)%4) * 1024 + int(i/256) * 256 + i%64 + mod_cnt*64] = data_in - ZERO_POINT_IN;
	}
    mod_cnt = mod_cnt + 1;
	std::cout << "done!\n";

	if(mod_cnt == 4)
	{
		mod_cnt = 0;
		int output_dim = 10;
		int input_dim = 4096;
		int output_vals[10] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

		for(int out = 0; out < output_dim; out++)
		{
			int sum = 0;
			for(int w = 0; w < input_dim; w++)
			{
				sum += weights_data[w][out] * features[w];
			}
			output_vals[out] = sum;
		}

		XTime_GetTime(&tEnd);
		xil_printf("Elapsed time: %d ms (%d ticks)\r\n", (tEnd - tStart)/100000, tEnd - tStart);

		std::cout << "Output result: ";
		for(int i = 9; i >= 0; i--)
		{
			if(i > 0)
				std::cout << output_vals[i] << ", ";
			else
				std::cout << output_vals[i] << std::endl;
		}

		int index = 0;
		int value = -1000000;
		for(int i = 0; i < 10; i++)
		{
			if(output_vals[i] > value)
			{
				value = output_vals[i];
				index = i;
			}
		}
		index = 9-index;
		std::cout << "True class: " << mnist_class << ", predicted class: " << index << std::endl;
	}
}

int SDsetup(void)
{
	FRESULT res;
	res = f_mount(&fatfs, Path, 0);
	if (res != FR_OK)
	{
		xil_printf("F_MOUNT ERROR CODE: %d; \r\n", res);
		return XST_FAILURE;
	}
	return XST_SUCCESS;
}

int loadFile(u8 *dataPtr, char *FileName, int nBytes)
{
	FRESULT Res;
	UINT NumBytesRead;

	Res = f_open(&fil, FileName, FA_OPEN_EXISTING | FA_READ);
	if (Res)
	{
		return XST_FAILURE;
	}

	Res = f_lseek(&fil, 0);
	if (Res)
	{
		return XST_FAILURE;
	}

	Res = f_read(&fil, (void*)DestinationAddress, nBytes, &NumBytesRead);
	if (Res)
	{
		return XST_FAILURE;
	}

	Res = f_sync(&fil);
	if (Res)
	{
		return XST_FAILURE;
	}

	Res = f_close(&fil);
	if (Res)
	{
		return XST_FAILURE;
	}

	return XST_SUCCESS;
}