import numpy as np
import matplotlib.pyplot as plt
import os

def main(file):
    x, y, t, p = np.loadtxt(file, unpack=True)


    img = np.zeros((128, 128, 3))

    for xi, yi, ti, pi in zip(x, y, t, p):
        if pi > 0:
            img[127-int(xi), 127-int(yi), 0] = 1
        else:
            img[127-int(xi), 127-int(yi), 2] = 1

    # 2d plot
    fig = plt.figure()
    plt.imshow(img)
    plt.title('2D plot of events')
    plt.show(block=False)

    # 3d plot
    fig = plt.figure()
    ax = fig.add_subplot(111, projection='3d')
    ax.scatter(127-y, t, x, c=p, s=1, cmap='bwr')
    ax.set_xlabel('X')
    ax.set_ylabel('Time')
    ax.set_zlabel('Y')
    plt.title('3D plot of events')
    plt.show()


if __name__ == '__main__':
    # select name of file
    
    print("Enter class and number of file to visualise")
    print("To stop use Ctrl+C")
    print("To show next file, close both windows\n")

    while True:
        cls = input("Enter class (0-9): ")
        idx = input("Enter number of file (0-9): ")


        name = f"m{cls}{idx}.txt"

        if name in os.listdir("sd"):
            main("sd/"+name)

        else:
            print("File not found")
            break