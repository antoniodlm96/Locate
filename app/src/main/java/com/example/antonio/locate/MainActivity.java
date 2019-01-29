package com.example.antonio.locate;

import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends AppCompatActivity {

    private EditText txt1;
    private EditText txt2;
    private TextView edv1;


    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

    }

    protected  boolean ckPassword(EditText txt1, EditText txt2){
        return txt1.getText().toString().equals(txt2.getText().toString());
    }

    protected void onClick(View view){
        txt1 = findViewById(R.id.editText3);
        txt2 = findViewById(R.id.editText4);

        if(ckPassword(txt1, txt2)){
            Toast.makeText(this, "Acceso permitido" +
                    txt1.getText().toString() + txt2.getText().toString(), Toast.LENGTH_LONG).show();
        } else {
            Toast.makeText(this, "Acceso denegado" +
                    txt1.getText().toString() + txt2.getText().toString(), Toast.LENGTH_LONG).show();
        }
    }

}
